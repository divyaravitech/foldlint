import Foundation

public enum OutputFormat: String, CaseIterable {
    /// Xcode-compatible `file:line:col: warning: message` lines and a summary.
    case text
    case json
    /// GitHub Actions workflow commands (inline PR annotations).
    case github
    /// SARIF 2.1.0 for GitHub code scanning and other tools.
    case sarif
    /// A Markdown table for PR comments and job summaries.
    case markdown
}

public enum Reporter {
    public static func render(_ result: LintResult, format: OutputFormat, useColor: Bool = false) -> String {
        switch format {
        case .text: return text(result, useColor: useColor)
        case .json: return json(result)
        case .github: return github(result)
        case .sarif: return sarif(result)
        case .markdown: return markdown(result)
        }
    }

    // MARK: Text

    static func text(_ result: LintResult, useColor: Bool) -> String {
        func paint(_ string: String, _ code: String) -> String {
            useColor ? "\u{1B}[\(code)m\(string)\u{1B}[0m" : string
        }
        var lines: [String] = []
        for finding in result.findings {
            let level: String
            switch finding.severity {
            case .error: level = paint("error", "1;31")
            case .warning: level = paint("warning", "1;33")
            // Xcode understands only `error`, `warning` and `note`.
            case .info: level = paint("note", "1;36")
            }
            lines.append("\(finding.file):\(finding.line):\(finding.column): \(level): \(finding.message) [\(finding.ruleID)]")
            lines.append(paint("    fix: \(finding.fix)", "2"))
        }

        let score = result.score
        let filled = Int((Double(score.value) / 100.0 * 30.0).rounded())
        let bar = String(repeating: "█", count: filled) + String(repeating: "░", count: 30 - filled)
        let barColor = score.value >= 90 ? "32" : score.value >= 70 ? "33" : "31"
        let counts = Dictionary(grouping: result.findings, by: \.severity).mapValues(\.count)
        let top = score.countsByRule.sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }.prefix(3)

        if !lines.isEmpty { lines.append("") }
        lines.append(paint("iPhone Duo readiness: \(score.value)/100 · \(score.grade)", "1"))
        lines.append(paint(bar, barColor))
        lines.append("\(counts[.error] ?? 0) errors · \(counts[.warning] ?? 0) warnings · \(counts[.info] ?? 0) notes · \(result.filesScanned) files scanned")
        if result.baselinedCount > 0 {
            lines.append("\(result.baselinedCount) known findings hidden by the baseline (still counted in the score)")
        }
        if !top.isEmpty {
            lines.append("Top issues: " + top.map { "\($0.key) (\($0.value))" }.joined(separator: ", "))
        }
        return lines.joined(separator: "\n")
    }

    // MARK: JSON

    struct JSONReport: Codable {
        let tool: String
        let version: String
        let score: Int
        let grade: String
        let filesScanned: Int
        let baselinedCount: Int
        let countsByRule: [String: Int]
        let findings: [Finding]
        let warnings: [String]
    }

    static func json(_ result: LintResult) -> String {
        let report = JSONReport(
            tool: "foldlint",
            version: FoldLintVersion.current,
            score: result.score.value,
            grade: result.score.grade,
            filesScanned: result.filesScanned,
            baselinedCount: result.baselinedCount,
            countsByRule: result.score.countsByRule,
            findings: result.findings,
            warnings: result.warnings
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = (try? encoder.encode(report)) ?? Data()
        return String(decoding: data, as: UTF8.self)
    }

    // MARK: GitHub

    static func github(_ result: LintResult) -> String {
        func escapeData(_ string: String) -> String {
            string.replacingOccurrences(of: "%", with: "%25")
                .replacingOccurrences(of: "\r", with: "%0D")
                .replacingOccurrences(of: "\n", with: "%0A")
        }
        func escapeProperty(_ string: String) -> String {
            escapeData(string)
                .replacingOccurrences(of: ":", with: "%3A")
                .replacingOccurrences(of: ",", with: "%2C")
        }
        var lines = result.findings.map { finding -> String in
            let command: String
            switch finding.severity {
            case .error: command = "error"
            case .warning: command = "warning"
            case .info: command = "notice"
            }
            let title = escapeProperty("FoldLint: \(finding.ruleID)")
            let message = escapeData("\(finding.message)\nFix: \(finding.fix)")
            return "::\(command) file=\(escapeProperty(finding.file)),line=\(finding.line),col=\(finding.column),title=\(title)::\(message)"
        }
        lines.append("iPhone Duo readiness: \(result.score.value)/100 (\(result.score.grade))")
        return lines.joined(separator: "\n")
    }

    // MARK: SARIF

    static func sarif(_ result: LintResult) -> String {
        func level(_ severity: Severity) -> String {
            switch severity {
            case .error: return "error"
            case .warning: return "warning"
            case .info: return "note"
            }
        }
        let rules: [[String: Any]] = result.rules.map { rule in
            let entry: [String: Any] = [
                "id": rule.id,
                "name": rule.name,
                "shortDescription": ["text": rule.name],
                "fullDescription": ["text": rule.summary],
                "help": ["text": rule.fix],
                "helpUri": rule.reference,
                "defaultConfiguration": ["level": level(rule.severity)],
            ]
            return entry
        }
        let results: [[String: Any]] = result.findings.map { finding in
            let region: [String: Any] = ["startLine": finding.line, "startColumn": finding.column]
            let physicalLocation: [String: Any] = [
                "artifactLocation": ["uri": finding.file],
                "region": region,
            ]
            let location: [String: Any] = ["physicalLocation": physicalLocation]
            let entry: [String: Any] = [
                "ruleId": finding.ruleID,
                "level": level(finding.severity),
                "message": ["text": "\(finding.message) Fix: \(finding.fix)"],
                "locations": [location],
                "partialFingerprints": ["foldlint/v1": finding.fingerprint],
            ]
            return entry
        }
        let driver: [String: Any] = [
            "name": "FoldLint",
            "version": FoldLintVersion.current,
            "informationUri": "https://github.com/divyaravitech/foldlint",
            "rules": rules,
        ]
        let run: [String: Any] = [
            "tool": ["driver": driver],
            "results": results,
            "properties": ["readinessScore": result.score.value],
        ]
        let log: [String: Any] = [
            "$schema": "https://json.schemastore.org/sarif-2.1.0.json",
            "version": "2.1.0",
            "runs": [run],
        ]
        let data = (try? JSONSerialization.data(withJSONObject: log, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])) ?? Data()
        return String(decoding: data, as: UTF8.self)
    }

    // MARK: Markdown

    static func markdown(_ result: LintResult) -> String {
        let score = result.score
        var lines = [
            "### 📱 iPhone Duo readiness: **\(score.value)/100** · \(score.grade)",
            "",
        ]
        if result.findings.isEmpty {
            lines.append("No issues found in \(result.filesScanned) files. 🎉")
            return lines.joined(separator: "\n")
        }
        lines.append("| Rule | Count | Severity | Fix |")
        lines.append("| --- | ---: | --- | --- |")
        let byID = Dictionary(uniqueKeysWithValues: result.rules.map { ($0.id, $0) })
        for (id, count) in score.countsByRule.sorted(by: { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }) {
            let rule = byID[id]
            let link = rule.map { "[`\(id)`](\($0.reference))" } ?? "`\(id)`"
            lines.append("| \(link) | \(count) | \(rule?.severity.rawValue ?? "-") | \(rule?.fix.replacingOccurrences(of: "|", with: "\\|") ?? "") |")
        }
        lines.append("")
        lines.append("<details><summary>All \(result.findings.count) findings</summary>")
        lines.append("")
        for finding in result.findings {
            lines.append("- `\(finding.file):\(finding.line)` **\(finding.ruleID)**: \(finding.message)")
        }
        lines.append("")
        lines.append("</details>")
        return lines.joined(separator: "\n")
    }

    // MARK: Rule catalog

    /// Renders the rule catalog for `--list-rules`.
    public static func rules(_ rules: [RuleDescriptor], format: OutputFormat) -> String {
        switch format {
        case .json, .sarif:
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            return String(decoding: (try? encoder.encode(rules)) ?? Data(), as: UTF8.self)
        case .markdown:
            var lines = ["| Rule | Default | Weight | Summary |", "| --- | --- | ---: | --- |"]
            for rule in rules {
                lines.append("| [`\(rule.id)`](\(rule.reference)) | \(rule.severity.rawValue) | \(rule.weight) | \(rule.summary.replacingOccurrences(of: "|", with: "\\|")) |")
            }
            return lines.joined(separator: "\n")
        case .text, .github:
            let width = rules.map(\.id.count).max() ?? 0
            return rules.map { rule in
                let id = rule.id.padding(toLength: width, withPad: " ", startingAt: 0)
                let severity = rule.severity.rawValue.padding(toLength: 7, withPad: " ", startingAt: 0)
                let weight = "w\(rule.weight)".padding(toLength: 3, withPad: " ", startingAt: 0)
                return "\(id)  \(severity)  \(weight)  \(rule.name)"
            }.joined(separator: "\n")
        }
    }

    // MARK: Badge

    /// A shields.io endpoint JSON (https://shields.io/badges/endpoint-badge).
    public static func badge(_ score: ReadinessScore) -> String {
        """
        {"schemaVersion":1,"label":"iPhone Duo ready","message":"\(score.value)%","color":"\(score.color)"}
        """
    }
}
