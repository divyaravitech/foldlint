import FoldLintCore
import XCTest

final class ProjectTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("foldlint-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func write(_ relativePath: String, _ contents: String) throws {
        let url = root.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }

    private func plist(_ dict: [String: Any]) throws -> String {
        let data = try PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0)
        return String(decoding: data, as: UTF8.self)
    }

    func testAppDelegateWithoutScenesFlagged() throws {
        try write("App/AppDelegate.swift", """
        import UIKit
        @main
        class AppDelegate: UIResponder, UIApplicationDelegate {
            var window: UIWindow?
        }
        """)
        let result = try Linter().lint(paths: [root.path])
        XCTAssertEqual(result.findings.map(\.ruleID), ["scene-lifecycle"])
    }

    func testSceneDelegateSatisfiesLifecycle() throws {
        try write("App/AppDelegate.swift", "class AppDelegate: UIResponder, UIApplicationDelegate {}")
        try write("App/SceneDelegate.swift", "class SceneDelegate: UIResponder, UIWindowSceneDelegate {}")
        XCTAssertEqual(try Linter().lint(paths: [root.path]).findings, [])
    }

    func testSwiftUIAppSatisfiesLifecycle() throws {
        try write("App/AppDelegate.swift", "class AppDelegate: NSObject, UIApplicationDelegate {}")
        try write("App/MyApp.swift", """
        import SwiftUI
        @main
        struct MyApp: App {
            @UIApplicationDelegateAdaptor var delegate: AppDelegate
            var body: some Scene { WindowGroup { Text("Hi") } }
        }
        """)
        XCTAssertEqual(try Linter().lint(paths: [root.path]).findings, [])
    }

    func testPlistManifestSatisfiesLifecycleAndRequiresFullScreenFlagged() throws {
        try write("App/AppDelegate.swift", "class AppDelegate: UIResponder, UIApplicationDelegate {}")
        try write("App/Info.plist", try plist([
            "UIApplicationSceneManifest": ["UIApplicationSupportsMultipleScenes": true],
            "UIRequiresFullScreen": true,
        ]))
        let result = try Linter().lint(paths: [root.path])
        XCTAssertEqual(result.findings.map(\.ruleID), ["requires-full-screen"])
    }

    func testExcludedDirectoriesSkipped() throws {
        try write("Pods/Lib/Bad.swift", "let s = UIScreen.main.scale")
        try write(".build/x/Bad.swift", "let s = UIScreen.main.scale")
        try write("Sources/Good.swift", "let s = traitCollection.displayScale")
        let result = try Linter().lint(paths: [root.path])
        XCTAssertEqual(result.findings, [])
        XCTAssertEqual(result.filesScanned, 1)
    }

    func testMissingPathThrows() {
        XCTAssertThrowsError(try Linter().lint(paths: [root.appendingPathComponent("nope").path]))
    }

    // MARK: Examples

    private var examplesDirectory: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // FoldLintCoreTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // package root
            .appendingPathComponent("Examples")
    }

    func testBeforeExampleTriggersEveryRuleFamily() throws {
        let result = try Linter().lint(paths: [examplesDirectory.appendingPathComponent("BeforeDuo").path])
        XCTAssertEqual(Set(result.findings.map(\.ruleID)), [
            "uiscreen-main", "idiom-branching", "orientation-branching", "orientation-lock",
            "standalone-bar", "text-only-bar-item", "app-wide-window",
            "arrangement-in-scroll", "navigation-inside-arrangement",
            "video-mirroring", "front-camera-assumption", "camera-discovery", "scene-lifecycle",
        ])
        XCTAssertLessThan(result.score.value, 40)
    }

    func testAfterExampleIsClean() throws {
        let result = try Linter().lint(paths: [examplesDirectory.appendingPathComponent("AfterDuo").path])
        XCTAssertEqual(result.findings, [])
        XCTAssertEqual(result.score.value, 100)
    }

    // MARK: Score

    func testPerfectScore() throws {
        try write("Sources/Good.swift", "let s = traitCollection.displayScale")
        let result = try Linter().lint(paths: [root.path])
        XCTAssertEqual(result.score.value, 100)
        XCTAssertEqual(result.score.grade, "Duo Ready")
    }

    func testScoreDropsWithFindings() throws {
        try write("Sources/Bad.swift", """
        let a = UIScreen.main.scale
        let b = UIDevice.current.userInterfaceIdiom
        """)
        let result = try Linter().lint(paths: [root.path])
        let total = result.rules.reduce(0) { $0 + $1.weight }
        // uiscreen-main (w10) and idiom-branching (w8) each keep 30% of their weight.
        let expected = Int((100.0 * (Double(total) - 7.0 - 5.6) / Double(total)).rounded())
        XCTAssertEqual(result.score.value, expected)
        XCTAssertLessThan(result.score.value, 100)
    }

    func testManyFindingsApproachZero() {
        let rule = RuleDescriptor(id: "r", name: "r", severity: .warning, weight: 10, summary: "", fix: "", reference: "")
        let findings = (1...25).map { Finding(ruleID: "r", severity: .warning, message: "", fix: "", file: "f", line: $0, column: 1) }
        XCTAssertEqual(ReadinessScore(findings: findings, rules: [rule]).value, 0)
    }

    // MARK: Reporters

    func testReportersProduceOutput() throws {
        try write("Sources/Bad.swift", "let a = UIScreen.main.scale")
        let result = try Linter().lint(paths: [root.path])
        let text = Reporter.render(result, format: .text)
        XCTAssertTrue(text.contains(": warning: UIScreen.main"))
        XCTAssertTrue(text.contains("iPhone Duo readiness:"))

        let github = Reporter.render(result, format: .github)
        XCTAssertTrue(github.hasPrefix("::warning file="))

        let json = Reporter.render(result, format: .json)
        let object = try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any]
        XCTAssertEqual(object?["score"] as? Int, result.score.value)

        let sarif = Reporter.render(result, format: .sarif)
        let log = try JSONSerialization.jsonObject(with: Data(sarif.utf8)) as? [String: Any]
        XCTAssertEqual(log?["version"] as? String, "2.1.0")

        XCTAssertTrue(Reporter.render(result, format: .markdown).contains("uiscreen-main"))
        XCTAssertTrue(Reporter.badge(result.score).contains("\"schemaVersion\":1"))
    }

    func testFailLevels() {
        let warning = Finding(ruleID: "r", severity: .warning, message: "", fix: "", file: "f", line: 1, column: 1)
        XCTAssertFalse(FailLevel.error.fails(on: [warning]))
        XCTAssertTrue(FailLevel.warning.fails(on: [warning]))
        XCTAssertTrue(FailLevel.info.fails(on: [warning]))
        XCTAssertFalse(FailLevel.never.fails(on: [warning]))
    }
}
