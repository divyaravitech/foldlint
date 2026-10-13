import ArgumentParser
import FoldLintCore
import Foundation

extension OutputFormat: ExpressibleByArgument {}
extension FailLevel: ExpressibleByArgument {}

@main
struct FoldLintCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "foldlint",
        abstract: "Check a Swift project for iPhone Duo readiness.",
        discussion: """
        Scans .swift files and Info.plist files for patterns that break on iPhone Duo, \
        such as UIScreen.main, idiom checks, standalone bars, ArrangementView misuse and \
        camera mirroring, then prints a readiness score from 0 to 100.

        Suppress a finding with a comment:
          // foldlint:disable-next-line uiscreen-main
          // foldlint:disable-file idiom-branching

        Exit codes: 0 = passed, 1 = findings or score below --min-score, 64 = usage or configuration error.
        """,
        version: FoldLintVersion.current
    )

    @Argument(help: "Files or directories to lint.")
    var paths: [String] = ["."]

    @Option(name: .shortAndLong, help: "Output format: \(OutputFormat.allCases.map(\.rawValue).joined(separator: ", ")).")
    var format: OutputFormat = .text

    @Option(name: .shortAndLong, help: "Path to a config file. Defaults to ./.foldlint.json if present.")
    var config: String?

    @Option(name: .customLong("fail-on"), help: "Exit non-zero on findings at or above this level: error, warning, info, never.")
    var failOn: FailLevel?

    @Option(name: .customLong("min-score"), help: "Exit non-zero if the readiness score is below this value (0-100).")
    var minScore: Int?

    @Option(name: .shortAndLong, help: "Write the report to this file instead of stdout.")
    var output: String?

    @Option(help: "Also write a shields.io endpoint badge JSON to this path.")
    var badge: String?

    @Option(help: "Ignore findings recorded in this baseline file. Only new findings are reported and gated.")
    var baseline: String?

    @Option(name: .customLong("write-baseline"), help: "Record every current finding in a baseline file and exit 0.")
    var writeBaseline: String?

    @Option(name: .customLong("disable"), parsing: .upToNextOption, help: "Rule IDs to disable.")
    var disabledRules: [String] = []

    @Flag(name: .customLong("list-rules"), help: "List all rules (in the chosen --format) and exit.")
    var listRules = false

    @Flag(name: .customLong("no-color"), help: "Disable colored output.")
    var noColor = false

    func validate() throws {
        if let minScore, !(0...100).contains(minScore) {
            throw ValidationError("--min-score must be between 0 and 100.")
        }
        if baseline != nil && writeBaseline != nil {
            throw ValidationError("--baseline and --write-baseline can't be used together.")
        }
    }

    mutating func run() throws {
        if listRules {
            print(Reporter.rules(RuleRegistry.all, format: format))
            return
        }

        var configuration = try loadConfiguration()
        configuration.disabledRules += disabledRules
        for id in configuration.unknownRuleIDs {
            warn("unknown rule ID '\(id)' (see foldlint --list-rules)")
        }

        let loadedBaseline: Baseline?
        do {
            loadedBaseline = try baseline.map(Baseline.load(from:))
        } catch {
            throw ValidationError(String(describing: error))
        }

        let result: LintResult
        do {
            result = try Linter(configuration: configuration, baseline: loadedBaseline).lint(paths: paths)
        } catch {
            throw ValidationError(String(describing: error))
        }
        result.warnings.forEach(warn)

        if let writeBaseline {
            try Baseline(fingerprints: result.allFingerprints).write(to: writeBaseline)
            warn("wrote \(result.allFingerprints.count) findings to \(writeBaseline)", label: "note")
            return
        }

        let useColor = format == .text && output == nil && !noColor
            && isatty(STDOUT_FILENO) != 0 && ProcessInfo.processInfo.environment["NO_COLOR"] == nil
        let report = Reporter.render(result, format: format, useColor: useColor)

        if let output {
            try report.write(toFile: output, atomically: true, encoding: .utf8)
        } else {
            print(report)
        }
        if let badge {
            try Reporter.badge(result.score).write(toFile: badge, atomically: true, encoding: .utf8)
        }

        let failLevel = failOn ?? configuration.failOn
        if failLevel.fails(on: result.findings) {
            throw ExitCode.failure
        }
        if let scoreFloor = minScore ?? configuration.minScore, result.score.value < scoreFloor {
            warn("readiness score \(result.score.value) is below the minimum of \(scoreFloor)", label: "error")
            throw ExitCode.failure
        }
    }

    private func loadConfiguration() throws -> Configuration {
        let path: String
        if let config {
            path = config
        } else {
            let discovered = (FileManager.default.currentDirectoryPath as NSString)
                .appendingPathComponent(Configuration.defaultFileName)
            guard FileManager.default.fileExists(atPath: discovered) else { return Configuration() }
            path = discovered
        }
        for key in Configuration.unknownKeys(in: path) {
            warn("unknown key '\(key)' in \(path)")
        }
        do {
            return try Configuration.load(from: path)
        } catch {
            throw ValidationError(String(describing: error))
        }
    }

    private func warn(_ message: String) {
        warn(message, label: "warning")
    }

    private func warn(_ message: String, label: String) {
        FileHandle.standardError.write(Data("foldlint: \(label): \(message)\n".utf8))
    }
}
