import Foundation

/// Where IPTether keeps its files. The engine gets the same paths through environment variables.
public struct AppPaths: Equatable, Sendable {
    /// config.json, last-ip and the run lock.
    public var stateDir: URL
    public var logFile: URL

    public init(stateDir: URL, logFile: URL) {
        self.stateDir = stateDir
        self.logFile = logFile
    }

    /// ~/Library/Application Support/IPTether and ~/Library/Logs/IPTether/iptether.log
    public static var standard: AppPaths {
        let library = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library")
        return AppPaths(
            stateDir: library.appendingPathComponent("Application Support/IPTether"),
            logFile: library.appendingPathComponent("Logs/IPTether/iptether.log")
        )
    }

    public var configFile: URL { stateDir.appendingPathComponent("config.json") }
    public var lastIPFile: URL { stateDir.appendingPathComponent("last-ip") }

    /// Environment the engine reads its paths from.
    public var engineEnvironment: [String: String] {
        [
            "IPTETHER_STATE_DIR": stateDir.path,
            "IPTETHER_CONFIG": configFile.path,
            "IPTETHER_LOG": logFile.path,
        ]
    }

    /// The IP the engine last applied ("203.0.113.4"), or nil if it never finished a sync.
    public func lastSyncedIP() -> String? {
        guard let text = try? String(contentsOf: lastIPFile, encoding: .utf8) else { return nil }
        let cidr = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cidr.isEmpty else { return nil }
        return cidr.hasSuffix("/32") ? String(cidr.dropLast(3)) : cidr
    }
}

public enum ConfigStoreError: LocalizedError, Equatable {
    case unreadable(String)
    case invalid([String])

    public var errorDescription: String? {
        switch self {
        case .unreadable(let reason): return "config.json could not be read: \(reason)"
        case .invalid(let problems): return problems.joined(separator: " ")
        }
    }
}

/// Loads and saves config.json.
public struct ConfigStore: Sendable {
    public var paths: AppPaths

    public init(paths: AppPaths = .standard) {
        self.paths = paths
    }

    /// The saved config, or nil when there is none yet (first run).
    public func load() throws -> IPTetherConfig? {
        let url = paths.configFile
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(IPTetherConfig.self, from: data)
        } catch {
            throw ConfigStoreError.unreadable(error.localizedDescription)
        }
    }

    /// Writes the config atomically. Refuses a config the engine would reject.
    public func save(_ config: IPTetherConfig) throws {
        let problems = config.validationErrors()
        guard problems.isEmpty else { throw ConfigStoreError.invalid(problems) }
        try FileManager.default.createDirectory(at: paths.stateDir, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(config).write(to: paths.configFile, options: .atomic)
    }
}
