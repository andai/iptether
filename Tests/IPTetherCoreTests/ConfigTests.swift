import Foundation
import Testing
@testable import IPTetherCore

@Suite struct ConfigTests {
    @Test func emptyFileGetsDefaults() throws {
        let config = try JSONDecoder().decode(IPTetherConfig.self, from: Data("{}".utf8))
        #expect(config.port == 22)
        #expect(config.aws.enabled && config.aws.regions.isEmpty)
        #expect(config.azure.enabled && config.azure.subscriptions.isEmpty)
        #expect(config.prod.exclude)
        #expect(config.prod.tagValues == ["prod", "production"])
        #expect(config.schedule.automatic == false)
        #expect(config.schedule.dailySweep == "09:30")
        #expect(config.ipServices == IPTetherConfig.defaultIPServices)
        #expect(!config.tag.isEmpty)
    }

    @Test func ipServicesMustBeHTTPS() {
        var config = IPTetherConfig(tag: "t")
        config.ipServices = ["https://ip.example.test/raw"]
        #expect(config.validationErrors().isEmpty)
        for bad in [[], ["http://ip.example.test"], ["https://"], ["ip.example.test"], ["https://ok.test", "ftp://x.test"]] {
            config.ipServices = bad
            #expect(config.validationErrors().count == 1, "should reject \(bad)")
        }
    }

    @Test func partialFileKeepsWhatItSets() throws {
        let json = #"{"version":1,"tag":"t1","azure":{"subscriptions":["a"]},"prod":{"allow":["x"]}}"#
        let config = try JSONDecoder().decode(IPTetherConfig.self, from: Data(json.utf8))
        #expect(config.tag == "t1")
        #expect(config.azure.enabled)
        #expect(config.azure.subscriptions == ["a"])
        #expect(config.prod.allow == ["x"])
        #expect(config.prod.exclude)
    }

    @Test func dailySweepOffSurvivesReload() throws {
        var config = IPTetherConfig(tag: "t")
        config.schedule.dailySweep = nil
        let data = try JSONEncoder().encode(config)
        #expect(String(decoding: data, as: UTF8.self).contains(#""dailySweep":null"#))
        let back = try JSONDecoder().decode(IPTetherConfig.self, from: data)
        #expect(back.schedule.dailySweep == nil)
        #expect(back == config)
    }

    @Test(arguments: [
        ("jdoe", "Janes-MacBook-Pro", "jdoe-janes-macbook-pro"),
        ("Jane Doe", "Jane's Mac", "jane-doe-jane-s-mac"),
        ("ö", "host_1.local", "--host_1.local"),
    ])
    func defaultTagMatchesEngineRule(user: String, host: String, expected: String) {
        #expect(IPTetherConfig.defaultTag(user: user, host: host) == expected)
    }

    @Test func validationCatchesBadValues() {
        var config = IPTetherConfig(tag: "bad tag!")
        config.port = 0
        config.schedule.intervalSeconds = 10
        config.schedule.dailySweep = "9.30"
        config.prod.namePattern = "("
        config.ipServices = ["http://insecure.test"]
        #expect(config.validationErrors().count == 6)
        #expect(IPTetherConfig(tag: "ok-tag_1.x").validationErrors().isEmpty)
    }

    @Test func storeRoundTripAndRefusesInvalid() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = ConfigStore(paths: AppPaths(stateDir: dir, logFile: dir.appendingPathComponent("log")))
        #expect(try store.load() == nil)

        var config = IPTetherConfig(tag: "round-trip")
        config.aws.regions = ["eu-west-1"]
        try store.save(config)
        #expect(try store.load() == config)

        #expect(throws: ConfigStoreError.self) { try store.save(IPTetherConfig(tag: "has space")) }
        #expect(try store.load() == config)   // the bad save left the file alone
    }

    /// The engine reads config.json with plutil, key path by key path. Check it sees what the app wrote.
    @Test func engineCanReadWhatTheAppWrites() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let paths = AppPaths(stateDir: dir, logFile: dir.appendingPathComponent("log"))
        var config = IPTetherConfig(tag: "plutil-check")
        config.azure.subscriptions = ["sub-a", "sub-b"]
        config.prod.allow = ["web-nsg"]
        config.aws.enabled = false
        config.ipServices = ["https://ip.example.test", "https://backup.example.test"]
        try ConfigStore(paths: paths).save(config)

        func extract(_ key: String) throws -> String {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/plutil")
            p.arguments = ["-extract", key, "raw", "-o", "-", paths.configFile.path]
            let pipe = Pipe()
            p.standardOutput = pipe
            try p.run()
            p.waitUntilExit()
            return String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        #expect(try extract("version") == "1")
        #expect(try extract("tag") == "plutil-check")
        #expect(try extract("aws.enabled") == "false")
        #expect(try extract("azure.subscriptions") == "2")
        #expect(try extract("azure.subscriptions.1") == "sub-b")
        #expect(try extract("prod.allow.0") == "web-nsg")
        #expect(try extract("prod.namePattern") == "prod")
        #expect(try extract("ipServices") == "2")
        #expect(try extract("ipServices.1") == "https://backup.example.test")
    }
}

@Suite struct ScheduleTests {
    @Test(arguments: ["09:30", "0:05", "23:59"])
    func parsesValidTimes(_ text: String) {
        #expect(DailyTime(text) != nil)
    }

    @Test(arguments: ["9.30", "24:00", "12:60", "12:5", "", "ab:cd", "1:2:3"])
    func rejectsInvalidTimes(_ text: String) {
        #expect(DailyTime(text) == nil)
    }

    @Test func nextIsLaterTodayOrTomorrow() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Kolkata")!
        let time = try #require(DailyTime("09:30"))
        let morning = calendar.date(from: DateComponents(year: 2026, month: 10, day: 26, hour: 8, minute: 0))!
        let evening = calendar.date(from: DateComponents(year: 2026, month: 10, day: 26, hour: 18, minute: 0))!
        let exactly = calendar.date(from: DateComponents(year: 2026, month: 10, day: 26, hour: 9, minute: 30))!

        let fromMorning = try #require(time.next(after: morning, calendar: calendar))
        #expect(calendar.dateComponents([.day, .hour, .minute], from: fromMorning) == DateComponents(day: 26, hour: 9, minute: 30))
        let fromEvening = try #require(time.next(after: evening, calendar: calendar))
        #expect(calendar.dateComponents([.day, .hour, .minute], from: fromEvening) == DateComponents(day: 27, hour: 9, minute: 30))
        let fromExactly = try #require(time.next(after: exactly, calendar: calendar))
        #expect(calendar.component(.day, from: fromExactly) == 27)
    }
}
