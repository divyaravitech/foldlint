import Foundation

public enum FoldLintVersion {
    public static let current = "0.1.0"
}

/// How serious a finding is.
public enum Severity: String, Codable, CaseIterable, Comparable {
    case info
    case warning
    case error

    var rank: Int {
        switch self {
        case .info: return 0
        case .warning: return 1
        case .error: return 2
        }
    }

    public static func < (lhs: Severity, rhs: Severity) -> Bool {
        lhs.rank < rhs.rank
    }
}

/// Static metadata describing a rule.
public struct RuleDescriptor: Codable, Hashable {
    /// Stable kebab-case identifier, used in config and suppression comments.
    public let id: String
    /// Short human title.
    public let name: String
    /// Default severity.
    public let severity: Severity
    /// Contribution to the readiness score (higher means more important).
    public let weight: Int
    /// One-line description of the problem, used as the finding message.
    public let summary: String
    /// One-line description of the fix.
    public let fix: String
    /// Link to Apple guidance or the gotchas doc.
    public let reference: String

    public init(id: String, name: String, severity: Severity, weight: Int, summary: String, fix: String, reference: String) {
        self.id = id
        self.name = name
        self.severity = severity
        self.weight = weight
        self.summary = summary
        self.fix = fix
        self.reference = reference
    }
}

/// A single problem found in a file.
public struct Finding: Codable, Hashable {
    public let ruleID: String
    public var severity: Severity
    public let message: String
    public let fix: String
    public var file: String
    public let line: Int
    public let column: Int
    /// A stable identifier that survives unrelated edits (line shifts), used by baselines
    /// and SARIF `partialFingerprints`. Empty until the linter assigns it.
    public var fingerprint: String

    public init(ruleID: String, severity: Severity, message: String, fix: String, file: String, line: Int, column: Int, fingerprint: String = "") {
        self.ruleID = ruleID
        self.severity = severity
        self.message = message
        self.fix = fix
        self.file = file
        self.line = line
        self.column = column
        self.fingerprint = fingerprint
    }
}

extension RuleDescriptor {
    func finding(file: String, line: Int, column: Int, message: String? = nil) -> Finding {
        Finding(
            ruleID: id,
            severity: severity,
            message: message ?? summary,
            fix: fix,
            file: file,
            line: line,
            column: column
        )
    }
}
