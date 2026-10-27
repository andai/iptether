import Foundation
import Testing
@testable import IPTetherCore

@Suite struct EngineTests {
    @Test func modesMapToEngineFlags() {
        #expect(SyncMode.sync.arguments == [])
        #expect(SyncMode.full.arguments == ["--full"])
        #expect(SyncMode.preview.arguments == ["--dry-run"])
        #expect(SyncMode.remove.arguments == ["--remove"])
    }

    @Test(arguments: [
        (Int32(0), SyncOutcome.Result.ok),
        (Int32(1), .failures),
        (Int32(75), .skipped),
        (Int32(2), .error(2)),
        (Int32(127), .error(127)),
    ])
    func exitCodesMapToResults(code: Int32, expected: SyncOutcome.Result) {
        let outcome = SyncOutcome(mode: .sync, exitCode: code, output: "")
        #expect(outcome.result == expected)
        #expect(outcome.isEngineError == (code != 0 && code != 1 && code != 75))
    }

    @Test func previewSummaryCountsDryLines() {
        let output = """
        2026-10-26 10:00:00 public IP = 203.0.113.4/32 (was: none)  dry=1 full=0 remove=0
        2026-10-26 10:00:01 AWS r1 sg-a (app): add 203.0.113.4/32
            DRY: aws ec2 authorize-security-group-ingress --region r1 --group-id sg-a
            DRY: aws ec2 revoke-security-group-ingress --region r1 --group-id sg-a --security-group-rule-ids sgr-1
        2026-10-26 10:00:02 AWS r1 sg-p (shop-prod): production, not managed
        2026-10-26 10:00:03 Azure web-nsg: set 203.0.113.4/32 (rule exists, prio 3999)
            DRY: az network nsg rule update --subscription s -g rg --nsg-name web-nsg
            DRY: az network nsg rule create --subscription s -g rg --nsg-name new-nsg
            DRY: az network nsg rule delete --subscription s -g rg --nsg-name db-prod-nsg
        2026-10-26 10:00:04 Azure db-prod-nsg: production, not managed
        """
        let summary = PreviewSummary(output: output)
        #expect(summary.adds == 2)
        #expect(summary.updates == 1)
        #expect(summary.removes == 2)
        #expect(summary.production == 2)
        #expect(summary.changeCount == 5)
    }

    @Test func lastSyncedIPStripsMask() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let paths = AppPaths(stateDir: dir, logFile: dir.appendingPathComponent("log"))
        #expect(paths.lastSyncedIP() == nil)
        try "203.0.113.4/32\n".write(to: paths.lastIPFile, atomically: true, encoding: .utf8)
        #expect(paths.lastSyncedIP() == "203.0.113.4")
    }

    @Test func missingEngineIsAnEngineError() async {
        let runner = EngineRunner(engineURL: URL(fileURLWithPath: "/nonexistent/iptether-sync.sh"))
        let outcome = await runner.run(.sync)
        #expect(outcome.exitCode == 127)
        #expect(outcome.isEngineError)
    }

    /// Runs a fake engine that records its arguments and environment.
    @Test func runnerPassesFlagsAndPaths() async throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let fake = dir.appendingPathComponent("fake-engine.sh")
        try """
        echo "args=$*"
        echo "state=$IPTETHER_STATE_DIR"
        echo "config=$IPTETHER_CONFIG"
        echo "log=$IPTETHER_LOG"
        echo "path=$PATH"
        exit 75
        """.write(to: fake, atomically: true, encoding: .utf8)
        let paths = AppPaths(stateDir: dir.appendingPathComponent("state"), logFile: dir.appendingPathComponent("logs/x.log"))
        let outcome = await EngineRunner(engineURL: fake, paths: paths, searchPath: "/custom/bin:/usr/bin:/bin").run(.full)
        #expect(outcome.result == .skipped)
        #expect(outcome.output.contains("args=--full"))
        #expect(outcome.output.contains("state=\(paths.stateDir.path)"))
        #expect(outcome.output.contains("config=\(paths.configFile.path)"))
        #expect(outcome.output.contains("log=\(paths.logFile.path)"))
        #expect(outcome.output.contains("path=/custom/bin:/usr/bin:/bin"))
    }

    /// The real engine, driven by the app's runner, against stub curl/aws/az. Nothing reaches a cloud.
    @Test func realEnginePreviewThroughRunner() async throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let bin = dir.appendingPathComponent("bin")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        try stub(bin, "curl", "echo 198.51.100.7")
        try stub(bin, "aws", """
        case "$*" in
          *describe-regions*) echo r1 ;;
          *describe-security-groups*) printf 'sg-a\\tapp-sg\\t\\nsg-p\\tweb-prod-sg\\t\\n' ;;
        esac
        """)
        try stub(bin, "az", "exit 0")

        let paths = AppPaths(stateDir: dir.appendingPathComponent("state"), logFile: dir.appendingPathComponent("state/iptether.log"))
        var config = IPTetherConfig(tag: "runner-test")
        config.azure.enabled = false
        try ConfigStore(paths: paths).save(config)

        let engine = engineScriptURL()
        let outcome = await EngineRunner(engineURL: engine, paths: paths, searchPath: "\(bin.path):/usr/bin:/bin").run(.preview)
        #expect(outcome.result == .ok, "engine output:\n\(outcome.output)")
        #expect(outcome.output.contains("DRY: aws ec2 authorize-security-group-ingress --region r1 --group-id sg-a"))
        #expect(outcome.output.contains("Description=ssh-autosync:runner-test"))
        #expect(outcome.output.contains("sg-p (web-prod-sg): production, not managed"))
        #expect(PreviewSummary(output: outcome.output).adds == 1)
        #expect(paths.lastSyncedIP() == nil)   // a preview never records state
        #expect(FileManager.default.fileExists(atPath: paths.logFile.path))
    }
}

private func tempDir() throws -> URL {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("iptether-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}

private func stub(_ dir: URL, _ name: String, _ body: String) throws {
    let url = dir.appendingPathComponent(name)
    try "#!/bin/bash\n\(body)\n".write(to: url, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
}

/// engine/iptether-sync.sh in this checkout.
private func engineScriptURL(file: String = #filePath) -> URL {
    URL(fileURLWithPath: file)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("engine/iptether-sync.sh")
}
