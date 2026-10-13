@testable import FoldLintCore
import XCTest

/// Engine-level behavior: baselines, fingerprints, determinism, configuration and rule metadata.
final class CoreBehaviorTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("foldlint-core-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    @discardableResult
    private func write(_ relativePath: String, _ contents: String) throws -> String {
        let url = root.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try contents.write(to: url, atomically: true, encoding: .utf8)
        return url.path
    }

    private var packageRoot: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    // MARK: Fingerprints

    func testFingerprintsSurviveLineShifts() {
        let before = Linter().lint(source: "let s = UIScreen.main.scale", path: "A.swift")
        let after = Linter().lint(source: "// a new comment\n\nlet s = UIScreen.main.scale", path: "A.swift")
        XCTAssertEqual(before.count, 1)
        XCTAssertNotEqual(before.first?.line, after.first?.line)
        XCTAssertEqual(before.first?.fingerprint, after.first?.fingerprint)
        XCTAssertEqual(before.first?.fingerprint.count, 16)
    }

    func testIdenticalLinesGetDistinctFingerprints() {
        let findings = Linter().lint(source: "let s = UIScreen.main.scale\nlet s = UIScreen.main.scale", path: "A.swift")
        XCTAssertEqual(findings.count, 2)
        XCTAssertNotEqual(findings[0].fingerprint, findings[1].fingerprint)
    }

    func testFingerprintDependsOnFileAndRule() {
        let a = Linter().lint(source: "let s = UIScreen.main.scale", path: "A.swift")
        let b = Linter().lint(source: "let s = UIScreen.main.scale", path: "B.swift")
        XCTAssertNotEqual(a.first?.fingerprint, b.first?.fingerprint)
    }

    func testFNVIsStable() {
        // Guard against accidental algorithm changes, which would invalidate every user's baseline.
        XCTAssertEqual(Fingerprinter.fnv1a64(""), 0xcbf2_9ce4_8422_2325)
        XCTAssertEqual(Fingerprinter.fnv1a64("a"), 0xaf63_dc4c_8601_ec8c)
    }

    // MARK: Baseline

    func testBaselineHidesKnownFindingsButKeepsScore() throws {
        try write("Sources/A.swift", "let a = UIScreen.main.scale")
        let first = try Linter().lint(paths: [root.path])
        XCTAssertEqual(first.findings.count, 1)

        let baselinePath = root.appendingPathComponent("baseline.json").path
        try Baseline(fingerprints: first.allFingerprints).write(to: baselinePath)
        let baseline = try Baseline.load(from: baselinePath)

        // Unchanged code: nothing new to report, but the score still reflects the debt.
        let second = try Linter(baseline: baseline).lint(paths: [root.path])
        XCTAssertEqual(second.findings, [])
        XCTAssertEqual(second.baselinedCount, 1)
        XCTAssertEqual(second.score, first.score)

        // A new problem is reported even with the baseline.
        try write("Sources/A.swift", "let a = UIScreen.main.scale\nlet b = UIDevice.current.userInterfaceIdiom")
        let third = try Linter(baseline: baseline).lint(paths: [root.path])
        XCTAssertEqual(third.findings.map(\.ruleID), ["idiom-branching"])
    }

    func testBaselineRoundTripsAndRejectsGarbage() throws {
        let path = root.appendingPathComponent("b.json").path
        try Baseline(fingerprints: ["b", "a", "a"]).write(to: path)
        XCTAssertEqual(try Baseline.load(from: path).fingerprints, ["a", "b"])

        let bad = try write("bad.json", "{ nope")
        XCTAssertThrowsError(try Baseline.load(from: bad))
        let future = try write("future.json", #"{"version": 99, "tool": "foldlint", "fingerprints": []}"#)
        XCTAssertThrowsError(try Baseline.load(from: future))
    }

    // MARK: Determinism and robustness

    func testParallelLintingIsDeterministic() throws {
        for index in 0..<200 {
            try write("Sources/File\(index).swift", """
            let a\(index) = UIScreen.main.scale
            let b\(index) = UIDevice.current.userInterfaceIdiom
            """)
        }
        let first = try Linter().lint(paths: [root.path])
        XCTAssertEqual(first.findings.count, 400)
        for _ in 0..<3 {
            let again = try Linter().lint(paths: [root.path])
            XCTAssertEqual(again.findings, first.findings)
            XCTAssertEqual(again.score, first.score)
        }
    }

    func testUnreadableFileIsSkippedWithWarning() throws {
        let url = root.appendingPathComponent("Sources/Latin1.swift")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data([0x6C, 0x65, 0x74, 0x20, 0xE9, 0xFF]).write(to: url)
        try write("Sources/Good.swift", "let a = UIScreen.main.scale")
        let result = try Linter().lint(paths: [root.path])
        XCTAssertEqual(result.findings.map(\.ruleID), ["uiscreen-main"])
        XCTAssertEqual(result.warnings.count, 1)
        XCTAssertTrue(result.warnings[0].contains("Latin1.swift"))
    }

    func testAppDelegateConfigurationProviderSatisfiesLifecycle() throws {
        try write("App/AppDelegate.swift", """
        class AppDelegate: UIResponder, UIApplicationDelegate {
            func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
                UISceneConfiguration(name: "Default", sessionRole: connectingSceneSession.role)
            }
        }
        """)
        XCTAssertEqual(try Linter().lint(paths: [root.path]).findings, [])
    }

    // MARK: Configuration

    func testInvalidConfigurationReportsPath() throws {
        let path = try write(".foldlint.json", #"{"fail_on": "sometimes"}"#)
        XCTAssertThrowsError(try Configuration.load(from: path)) { error in
            guard case FoldLintError.invalidConfiguration(let errorPath, _) = error else {
                return XCTFail("unexpected error \(error)")
            }
            XCTAssertEqual(errorPath, path)
        }
    }

    func testUnknownKeysAndRuleIDsAreDetected() throws {
        let path = try write(".foldlint.json", #"{"disabled_rule": ["x"], "disabled_rules": ["not-a-rule", "uiscreen-main"]}"#)
        XCTAssertEqual(Configuration.unknownKeys(in: path), ["disabled_rule"])
        XCTAssertEqual(try Configuration.load(from: path).unknownRuleIDs, ["not-a-rule"])
    }

    func testOnlyRules() {
        var configuration = Configuration()
        configuration.onlyRules = ["idiom-branching"]
        let findings = Linter(configuration: configuration).lint(source: """
        let a = UIScreen.main.scale
        let b = UIDevice.current.userInterfaceIdiom
        """)
        XCTAssertEqual(findings.map(\.ruleID), ["idiom-branching"])
    }

    // MARK: Rule metadata and documentation drift

    func testRuleMetadataInvariants() {
        let rules = RuleRegistry.all
        XCTAssertEqual(Set(rules.map(\.id)).count, rules.count, "rule IDs must be unique")
        for rule in rules {
            XCTAssertNotNil(rule.id.range(of: "^[a-z][a-z0-9]*(-[a-z0-9]+)*$", options: .regularExpression), rule.id)
            XCTAssertGreaterThan(rule.weight, 0, rule.id)
            XCTAssertLessThanOrEqual(rule.weight, 10, rule.id)
            XCTAssertTrue(rule.reference.hasSuffix("#\(rule.id)"), rule.id)
            XCTAssertFalse(rule.summary.isEmpty, rule.id)
            XCTAssertFalse(rule.fix.isEmpty, rule.id)
        }
    }

    func testEveryRuleIsDocumented() throws {
        let rulesDoc = try String(contentsOf: packageRoot.appendingPathComponent("docs/rules.md"), encoding: .utf8)
        let readme = try String(contentsOf: packageRoot.appendingPathComponent("README.md"), encoding: .utf8)
        for rule in RuleRegistry.all {
            XCTAssertTrue(rulesDoc.contains("\n## \(rule.id)\n"), "docs/rules.md has no section for \(rule.id)")
            XCTAssertTrue(readme.contains("`\(rule.id)`"), "README.md doesn't list \(rule.id)")
        }
    }

    func testRuleCatalogFormats() throws {
        let json = Reporter.rules(RuleRegistry.all, format: .json)
        let decoded = try JSONDecoder().decode([RuleDescriptor].self, from: Data(json.utf8))
        XCTAssertEqual(decoded, RuleRegistry.all)
        XCTAssertTrue(Reporter.rules(RuleRegistry.all, format: .markdown).hasPrefix("| Rule |"))
    }

    func testSARIFHasFingerprints() throws {
        try write("Sources/A.swift", "let a = UIScreen.main.scale")
        let sarif = Reporter.render(try Linter().lint(paths: [root.path]), format: .sarif)
        let log = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(sarif.utf8)) as? [String: Any])
        let runs = try XCTUnwrap(log["runs"] as? [[String: Any]])
        let results = try XCTUnwrap(runs.first?["results"] as? [[String: Any]])
        let fingerprints = try XCTUnwrap(results.first?["partialFingerprints"] as? [String: String])
        XCTAssertEqual(fingerprints["foldlint/v1"]?.count, 16)
    }
}
