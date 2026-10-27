import AppKit
import Foundation
import IPTetherCore
import Network
import Observation
import ServiceManagement

/// App state and scheduling. Runs the engine on a timer, when the network changes,
/// after wake, and once a day for a full sweep, all only while Automatic Updates is on.
@MainActor
@Observable
final class AppModel {
    static let shared = AppModel()

    private(set) var config: IPTetherConfig
    /// Shown in the menu and Settings when config.json can't be read or saved.
    private(set) var configError: String?
    /// No config.json existed at launch: the user hasn't previewed or turned anything on yet.
    private(set) var needsSetup = false
    /// Set once on first launch so the menu bar label opens the Preview window; the label
    /// clears it with `takeSetupRequest()`.
    private(set) var setupWindowRequested = false

    private(set) var lastIP: String?
    private(set) var lastRun: Date?
    private(set) var lastOutcome: SyncOutcome?
    private(set) var isRunning = false

    /// The latest dry run, for the Preview window.
    private(set) var preview: SyncOutcome?

    let paths: AppPaths
    private let store: ConfigStore
    private let engine: EngineRunner?

    @ObservationIgnored private var intervalTask: Task<Void, Never>?
    @ObservationIgnored private var sweepTask: Task<Void, Never>?
    @ObservationIgnored private var networkDebounce: Task<Void, Never>?
    @ObservationIgnored private var pathMonitor: NWPathMonitor?
    @ObservationIgnored private var lastPathDescription: String?
    @ObservationIgnored private var wakeObserver: NSObjectProtocol?

    private init(paths: AppPaths = .standard) {
        self.paths = paths
        store = ConfigStore(paths: paths)
        engine = EngineRunner.locateEngine().map { EngineRunner(engineURL: $0, paths: paths) }
        config = .firstRun()
    }

    // MARK: Startup

    func start() {
        do {
            if let saved = try store.load() {
                config = saved
            } else {
                // first run: write a config with automatic updates off, so nothing changes until the user previews
                needsSetup = true
                setupWindowRequested = true
                try store.save(config)
            }
        } catch {
            configError = error.localizedDescription
        }
        lastIP = paths.lastSyncedIP()
        startNetworkMonitor()
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.runIfAutomatic(.sync) }
        }
        reschedule()
    }

    // MARK: Menu state

    var iconName: String {
        if isRunning { return "arrow.triangle.2.circlepath" }
        if configError != nil || engine == nil { return "exclamationmark.shield" }
        switch lastOutcome?.result {
        case .failures?, .error?: return "exclamationmark.shield"
        default: return "lock.shield"
        }
    }

    var statusLine: String {
        if isRunning { return "Syncing…" }
        if needsSetup { return "Not set up yet" }
        guard let ip = lastIP else { return "Never synced" }
        if let lastRun { return "\(ip) · synced \(lastRun.formatted(date: .omitted, time: .shortened))" }
        return "Last synced \(ip)"
    }

    /// Something the user should act on, or nil.
    var warning: String? {
        if engine == nil { return "The sync engine is missing from the app." }
        if let configError { return configError }
        switch lastOutcome?.result {
        case .failures?, .error?: return lastOutcome?.summary
        default: return nil
        }
    }

    // MARK: Actions

    /// True once, when the first-run Preview window should open.
    func takeSetupRequest() -> Bool {
        defer { setupWindowRequested = false }
        return setupWindowRequested
    }

    func syncNow() { run(.sync) }
    func fullSweep() { run(.full) }

    /// Dry run for the Preview window. Changes nothing.
    func runPreview() async {
        guard let engine, !isRunning else { return }
        isRunning = true
        preview = await engine.run(.preview)
        isRunning = false
    }

    /// Applies the previewed changes, and optionally turns on automatic updates afterwards.
    func applyPreview(turnOnAutomatic: Bool) {
        if turnOnAutomatic {
            update { $0.schedule.automatic = true }
        }
        needsSetup = false
        run(.full)
    }

    /// Turns automatic updates off first, so no scheduled run adds the IP straight back.
    func removeMyIP() {
        update { $0.schedule.automatic = false }
        run(.remove)
    }

    func setAutomatic(_ on: Bool) {
        update { $0.schedule.automatic = on }
        if on { run(.sync) }
    }

    func openLog() {
        NSWorkspace.shared.open(paths.logFile)
    }

    func openConfigFolder() {
        NSWorkspace.shared.open(paths.stateDir)
    }

    /// Saves a config change and reschedules. An invalid change is kept in memory but not
    /// written, and the reason shows in Settings.
    func update(_ change: (inout IPTetherConfig) -> Void) {
        var next = config
        change(&next)
        guard next != config else { return }
        config = next
        do {
            try store.save(next)
            configError = nil
        } catch {
            configError = error.localizedDescription
        }
        reschedule()
    }

    // MARK: Launch at login

    var launchAtLogin: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// Returns an error message to show, or nil on success.
    func setLaunchAtLogin(_ on: Bool) -> String? {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    // MARK: Running the engine

    private func run(_ mode: SyncMode) {
        guard let engine, !isRunning else { return }
        isRunning = true
        Task {
            let outcome = await engine.run(mode)
            isRunning = false
            lastRun = Date()
            lastOutcome = outcome
            lastIP = paths.lastSyncedIP()
        }
    }

    private func runIfAutomatic(_ mode: SyncMode) {
        guard config.schedule.automatic, configError == nil else { return }
        run(mode)
    }

    // MARK: Scheduling

    private func reschedule() {
        intervalTask?.cancel()
        sweepTask?.cancel()
        guard config.schedule.automatic else { return }

        let interval = Duration.seconds(max(60, config.schedule.intervalSeconds))
        intervalTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: interval)
                guard !Task.isCancelled else { return }
                self?.runIfAutomatic(.sync)
            }
        }

        if let text = config.schedule.dailySweep, let time = DailyTime(text) {
            sweepTask = Task { [weak self] in
                while !Task.isCancelled {
                    guard let next = time.next(after: Date()) else { return }
                    // ContinuousClock keeps counting through system sleep, so a sweep missed
                    // while asleep runs right after wake
                    try? await Task.sleep(for: .seconds(next.timeIntervalSinceNow))
                    guard !Task.isCancelled else { return }
                    self?.runIfAutomatic(.full)
                }
            }
        }
    }

    private func startNetworkMonitor() {
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            let description = "\(path.status) \(path.availableInterfaces.map(\.name))"
            Task { @MainActor in self?.networkChanged(description, satisfied: path.status == .satisfied) }
        }
        monitor.start(queue: DispatchQueue(label: "IPTether.network"))
        pathMonitor = monitor
    }

    /// Syncs a few seconds after the network settles on a new path (Wi-Fi switch, VPN, tethering).
    private func networkChanged(_ description: String, satisfied: Bool) {
        defer { lastPathDescription = description }
        // the first callback only reports the current path
        guard lastPathDescription != nil, description != lastPathDescription, satisfied,
              config.schedule.syncOnNetworkChange else { return }
        networkDebounce?.cancel()
        networkDebounce = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            self?.runIfAutomatic(.sync)
        }
    }
}
