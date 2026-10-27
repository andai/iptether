import Foundation

/// Where GUI apps should look for `aws` and `az`: launchd gives them only /usr/bin:/bin.
public let defaultSearchPath = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

/// Output of a finished child process.
public struct CommandResult: Sendable {
    public var status: Int32
    public var stdout: String
    public var stderr: String
}

/// Runs a command off the main thread and collects its output.
public func runCommand(
    _ executable: String,
    _ arguments: [String],
    environment extra: [String: String] = [:],
    searchPath: String = defaultSearchPath
) async -> CommandResult {
    await withCheckedContinuation { continuation in
        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            var env = ProcessInfo.processInfo.environment
            env["PATH"] = searchPath
            env.merge(extra) { _, new in new }
            process.environment = env
            let out = Pipe(), err = Pipe()
            process.standardOutput = out
            process.standardError = err
            process.standardInput = FileHandle.nullDevice
            do {
                try process.run()
            } catch {
                continuation.resume(returning: CommandResult(status: -1, stdout: "", stderr: error.localizedDescription))
                return
            }
            // read stderr on its own queue so neither pipe can fill up and stall the child
            var errData = Data()
            let group = DispatchGroup()
            group.enter()
            DispatchQueue.global().async {
                errData = err.fileHandleForReading.readDataToEndOfFile()
                group.leave()
            }
            let outData = out.fileHandleForReading.readDataToEndOfFile()
            group.wait()
            process.waitUntilExit()
            continuation.resume(returning: CommandResult(
                status: process.terminationStatus,
                stdout: String(decoding: outData, as: UTF8.self),
                stderr: String(decoding: errData, as: UTF8.self)
            ))
        }
    }
}

// MARK: - Sync engine

public enum SyncMode: String, CaseIterable, Sendable {
    /// Only if the public IP changed since the last sync.
    case sync
    /// Every firewall, even when the IP is unchanged.
    case full
    /// Show what would change; change nothing.
    case preview
    /// Remove this Mac's own rules everywhere.
    case remove

    public var arguments: [String] {
        switch self {
        case .sync: return []
        case .full: return ["--full"]
        case .preview: return ["--dry-run"]
        case .remove: return ["--remove"]
        }
    }
}

public struct SyncOutcome: Equatable, Sendable {
    public enum Result: Equatable, Sendable {
        case ok
        /// Finished, but some firewall calls failed (exit 1).
        case failures
        /// Another run held the lock, or the IP changed mid-run (exit 75). The next run catches up.
        case skipped
        /// The engine could not start or stopped unexpectedly.
        case error(Int32)
    }

    public var mode: SyncMode
    public var exitCode: Int32
    public var output: String

    public var result: Result {
        switch exitCode {
        case 0: return .ok
        case 1: return .failures
        case 75: return .skipped
        default: return .error(exitCode)
        }
    }

    /// True when the engine itself failed, as opposed to some firewalls failing.
    public var isEngineError: Bool {
        if case .error = result { return true }
        return false
    }

    /// One line for the menu.
    public var summary: String {
        switch result {
        case .ok: return mode == .remove ? "Removed your IP" : "Synced"
        case .failures: return "Some firewalls failed. See the log."
        case .skipped: return "Skipped. Another sync was running or the IP changed."
        case .error(let code): return "The sync engine failed (code \(code))."
        }
    }
}

/// Runs `iptether-sync.sh` with this app's paths.
public struct EngineRunner: Sendable {
    public var engineURL: URL
    public var paths: AppPaths
    public var searchPath: String

    public init(engineURL: URL, paths: AppPaths = .standard, searchPath: String = defaultSearchPath) {
        self.engineURL = engineURL
        self.paths = paths
        self.searchPath = searchPath
    }

    /// The engine shipped inside the app, or `IPTETHER_ENGINE` when running from a checkout.
    public static func locateEngine(in bundle: Bundle = .main) -> URL? {
        if let override = ProcessInfo.processInfo.environment["IPTETHER_ENGINE"] {
            return URL(fileURLWithPath: override)
        }
        return bundle.url(forResource: "iptether-sync", withExtension: "sh")
    }

    public func run(_ mode: SyncMode) async -> SyncOutcome {
        guard FileManager.default.fileExists(atPath: engineURL.path) else {
            return SyncOutcome(mode: mode, exitCode: 127, output: "Engine not found at \(engineURL.path)")
        }
        let result = await runCommand(
            "/bin/bash", [engineURL.path] + mode.arguments,
            environment: paths.engineEnvironment, searchPath: searchPath
        )
        let output = result.stderr.isEmpty ? result.stdout : result.stdout + result.stderr
        return SyncOutcome(mode: mode, exitCode: result.status, output: output)
    }
}

// MARK: - Preview

/// What a dry run would do, counted from the engine's `DRY:` lines.
public struct PreviewSummary: Equatable, Sendable {
    public var adds = 0
    public var updates = 0
    public var removes = 0
    /// Firewalls skipped as production.
    public var production = 0

    public var changeCount: Int { adds + updates + removes }

    public init(output: String) {
        for line in output.split(separator: "\n") {
            if line.contains("DRY: aws ec2 authorize-security-group-ingress") || line.contains("DRY: az network nsg rule create") {
                adds += 1
            } else if line.contains("DRY: az network nsg rule update") {
                updates += 1
            } else if line.contains("DRY: aws ec2 revoke-security-group-ingress") || line.contains("DRY: az network nsg rule delete") {
                removes += 1
            } else if line.hasSuffix(": production, not managed") {
                production += 1
            }
        }
    }
}

// MARK: - CLI discovery

public struct AzureSubscription: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var state: String
    public var isDefault: Bool?
}

public enum Discovery {
    /// Whether a CLI is installed somewhere on the search path.
    public static func hasCLI(_ name: String, searchPath: String = defaultSearchPath) -> Bool {
        searchPath.split(separator: ":").contains {
            FileManager.default.isExecutableFile(atPath: "\($0)/\(name)")
        }
    }

    /// Subscriptions the current `az` login can see.
    public static func azureSubscriptions(searchPath: String = defaultSearchPath) async throws -> [AzureSubscription] {
        let r = await runCommand("/usr/bin/env", ["az", "account", "list", "-o", "json"], searchPath: searchPath)
        guard r.status == 0 else { throw DiscoveryError.cli(firstLine(r.stderr) ?? "az exited with \(r.status)") }
        return try JSONDecoder().decode([AzureSubscription].self, from: Data(r.stdout.utf8))
    }

    /// Regions enabled for the current `aws` login.
    public static func awsRegions(searchPath: String = defaultSearchPath) async throws -> [String] {
        let r = await runCommand(
            "/usr/bin/env",
            ["aws", "ec2", "describe-regions", "--region", "us-east-1", "--query", "Regions[].RegionName", "--output", "json"],
            searchPath: searchPath
        )
        guard r.status == 0 else { throw DiscoveryError.cli(firstLine(r.stderr) ?? "aws exited with \(r.status)") }
        return try JSONDecoder().decode([String].self, from: Data(r.stdout.utf8)).sorted()
    }

    private static func firstLine(_ text: String) -> String? {
        text.split(separator: "\n").first.map(String.init)
    }
}

public enum DiscoveryError: LocalizedError {
    case cli(String)
    public var errorDescription: String? {
        switch self { case .cli(let message): return message }
    }
}
