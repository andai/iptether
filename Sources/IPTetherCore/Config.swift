import Foundation

/// The settings file shared by the app and the engine (`config.json`).
///
/// The engine reads it with `plutil`, key path by key path, so the JSON keys here are
/// its contract: renaming a property means changing `engine/iptether-sync.sh` too.
/// Every key is optional when decoding, so hand-written or older files still load.
public struct IPTetherConfig: Codable, Equatable, Sendable {
    public var version: Int = 1
    /// Identifies this Mac's own rules: AWS description `ssh-autosync:<tag>`,
    /// Azure rule name `ssh-autosync-<tag>`.
    public var tag: String
    public var port: Int = 22
    public var aws = AWS()
    public var azure = Azure()
    public var prod = Prod()
    /// Services that return the caller's public IP as plain text, tried in order.
    /// Only https:// URLs are used.
    public var ipServices = IPTetherConfig.defaultIPServices
    /// Read by the app only; the engine ignores it.
    public var schedule = Schedule()

    public static let defaultIPServices = [
        "https://checkip.amazonaws.com",
        "https://ifconfig.me",
        "https://api.ipify.org",
    ]

    public struct AWS: Codable, Equatable, Sendable {
        public var enabled = true
        /// Empty means every region enabled for the account.
        public var regions: [String] = []
        public init() {}
        enum CodingKeys: String, CodingKey { case enabled, regions }
    }

    public struct Azure: Codable, Equatable, Sendable {
        public var enabled = true
        /// Empty means every enabled subscription the `az` login can see.
        public var subscriptions: [String] = []
        public init() {}
        enum CodingKeys: String, CodingKey { case enabled, subscriptions }
    }

    /// Production firewalls are left alone: nothing is added, and this Mac's own rule is removed.
    public struct Prod: Codable, Equatable, Sendable {
        public var exclude = true
        /// Extended regex, matched case-insensitively against the firewall name.
        public var namePattern = "prod"
        public var tagKeys = ["env", "environment"]
        public var tagValues = ["prod", "production"]
        /// Firewall names or ids to manage even when they look like production.
        public var allow: [String] = []
        public init() {}
        enum CodingKeys: String, CodingKey { case exclude, namePattern, tagKeys, tagValues, allow }
    }

    public struct Schedule: Codable, Equatable, Sendable {
        /// Off until the user has seen a preview and turned it on.
        public var automatic = false
        public var intervalSeconds = 180
        public var syncOnNetworkChange = true
        /// Local time "HH:mm" for a daily full sweep, or nil for none.
        public var dailySweep: String? = "09:30"
        public init() {}
        enum CodingKeys: String, CodingKey { case automatic, intervalSeconds, syncOnNetworkChange, dailySweep }
    }

    public init(tag: String) {
        self.tag = tag
    }

    /// A first-run config: `<user>-<host>` tag, everything else at its default.
    public static func firstRun(user: String = NSUserName(), host: String = shortHostName()) -> IPTetherConfig {
        IPTetherConfig(tag: defaultTag(user: user, host: host))
    }

    /// Same rule as the engine's DEFAULT_TAG: lowercased, anything outside [a-z0-9._-] becomes "-".
    public static func defaultTag(user: String, host: String) -> String {
        let allowed = Set("abcdefghijklmnopqrstuvwxyz0123456789._-")
        return String("\(user)-\(host)".lowercased().map { allowed.contains($0) ? $0 : "-" })
    }

    /// Problems that would make the engine refuse the file, in the order the user should fix them.
    public func validationErrors() -> [String] {
        var errors: [String] = []
        if tag.isEmpty || tag.range(of: #"^[A-Za-z0-9._-]+$"#, options: .regularExpression) == nil {
            errors.append("The tag may only use letters, digits, dots, underscores and hyphens.")
        }
        if !(1...65535).contains(port) {
            errors.append("The port must be between 1 and 65535.")
        }
        if schedule.intervalSeconds < 60 {
            errors.append("The sync interval must be at least 60 seconds.")
        }
        if let sweep = schedule.dailySweep, DailyTime(sweep) == nil {
            errors.append("The daily sweep time must look like 09:30.")
        }
        if (try? NSRegularExpression(pattern: prod.namePattern)) == nil {
            errors.append("The production name pattern is not a valid regular expression.")
        }
        if ipServices.isEmpty || !ipServices.allSatisfy(Self.isValidIPService) {
            errors.append("IP lookup services must be one or more https:// addresses.")
        }
        return errors
    }

    static func isValidIPService(_ text: String) -> Bool {
        guard let url = URL(string: text), url.scheme?.lowercased() == "https", let host = url.host else {
            return false
        }
        return !host.isEmpty
    }

    // MARK: Codable — every key optional

    enum CodingKeys: String, CodingKey {
        case version, tag, port, aws, azure, prod, ipServices, schedule
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        tag = try c.decodeIfPresent(String.self, forKey: .tag) ?? IPTetherConfig.firstRun().tag
        port = try c.decodeIfPresent(Int.self, forKey: .port) ?? 22
        aws = try c.decodeIfPresent(AWS.self, forKey: .aws) ?? AWS()
        azure = try c.decodeIfPresent(Azure.self, forKey: .azure) ?? Azure()
        prod = try c.decodeIfPresent(Prod.self, forKey: .prod) ?? Prod()
        ipServices = try c.decodeIfPresent([String].self, forKey: .ipServices) ?? IPTetherConfig.defaultIPServices
        schedule = try c.decodeIfPresent(Schedule.self, forKey: .schedule) ?? Schedule()
    }
}

extension IPTetherConfig.AWS {
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        regions = try c.decodeIfPresent([String].self, forKey: .regions) ?? []
    }
}

extension IPTetherConfig.Azure {
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        subscriptions = try c.decodeIfPresent([String].self, forKey: .subscriptions) ?? []
    }
}

extension IPTetherConfig.Prod {
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = IPTetherConfig.Prod()
        exclude = try c.decodeIfPresent(Bool.self, forKey: .exclude) ?? defaults.exclude
        namePattern = try c.decodeIfPresent(String.self, forKey: .namePattern) ?? defaults.namePattern
        tagKeys = try c.decodeIfPresent([String].self, forKey: .tagKeys) ?? defaults.tagKeys
        tagValues = try c.decodeIfPresent([String].self, forKey: .tagValues) ?? defaults.tagValues
        allow = try c.decodeIfPresent([String].self, forKey: .allow) ?? defaults.allow
    }
}

extension IPTetherConfig.Schedule {
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = IPTetherConfig.Schedule()
        automatic = try c.decodeIfPresent(Bool.self, forKey: .automatic) ?? defaults.automatic
        intervalSeconds = try c.decodeIfPresent(Int.self, forKey: .intervalSeconds) ?? defaults.intervalSeconds
        syncOnNetworkChange = try c.decodeIfPresent(Bool.self, forKey: .syncOnNetworkChange) ?? defaults.syncOnNetworkChange
        // an explicit null turns the sweep off; a missing key keeps the default
        dailySweep = c.contains(.dailySweep)
            ? try c.decodeIfPresent(String.self, forKey: .dailySweep)
            : defaults.dailySweep
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(automatic, forKey: .automatic)
        try c.encode(intervalSeconds, forKey: .intervalSeconds)
        try c.encode(syncOnNetworkChange, forKey: .syncOnNetworkChange)
        try c.encode(dailySweep, forKey: .dailySweep)   // writes null when off, so "off" survives a reload
    }
}

/// The short host name, like `hostname -s`.
public func shortHostName() -> String {
    var buffer = [CChar](repeating: 0, count: 256)
    guard gethostname(&buffer, buffer.count) == 0 else { return "mac" }
    let name = String(cString: buffer)
    return name.split(separator: ".").first.map(String.init) ?? name
}
