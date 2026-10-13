import Foundation

/// The lowest severity that makes `foldlint` exit with a failure.
public enum FailLevel: String, Codable, CaseIterable {
    case error
    case warning
    case info
    case never

    public func fails(on findings: [Finding]) -> Bool {
        let threshold: Severity
        switch self {
        case .never: return false
        case .error: threshold = .error
        case .warning: threshold = .warning
        case .info: threshold = .info
        }
        return findings.contains { $0.severity >= threshold }
    }
}

/// Options read from `.foldlint.json`. Every key is optional.
///
/// ```json
/// {
///   "disabled_rules": ["orientation-lock"],
///   "only_rules": null,
///   "excluded": ["Pods", "Vendor"],
///   "severity": { "text-only-bar-item": "warning" },
///   "fail_on": "error",
///   "min_score": 80
/// }
/// ```
public struct Configuration: Codable, Equatable {
    public static let defaultFileName = ".foldlint.json"
    public static let defaultExcluded = [
        ".build", ".git", ".swiftpm", "Pods", "Carthage", "DerivedData", "build", "node_modules", "fastlane",
    ]

    public var disabledRules: [String] = []
    public var onlyRules: [String]?
    public var excluded: [String] = Configuration.defaultExcluded
    public var severity: [String: Severity] = [:]
    public var failOn: FailLevel = .error
    public var minScore: Int?

    public init() {}

    enum CodingKeys: String, CodingKey {
        case disabledRules = "disabled_rules"
        case onlyRules = "only_rules"
        case excluded
        case severity
        case failOn = "fail_on"
        case minScore = "min_score"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        disabledRules = try container.decodeIfPresent([String].self, forKey: .disabledRules) ?? []
        onlyRules = try container.decodeIfPresent([String].self, forKey: .onlyRules)
        // User excludes are added to the defaults, not substituted for them.
        let userExcluded = try container.decodeIfPresent([String].self, forKey: .excluded) ?? []
        excluded = Configuration.defaultExcluded + userExcluded
        severity = try container.decodeIfPresent([String: Severity].self, forKey: .severity) ?? [:]
        failOn = try container.decodeIfPresent(FailLevel.self, forKey: .failOn) ?? .error
        minScore = try container.decodeIfPresent(Int.self, forKey: .minScore)
    }

    public static func load(from path: String) throws -> Configuration {
        let data: Data
        do {
            data = try Data(contentsOf: URL(fileURLWithPath: path))
        } catch {
            throw FoldLintError.invalidConfiguration(path: path, reason: "file could not be read")
        }
        do {
            return try JSONDecoder().decode(Configuration.self, from: data)
        } catch let DecodingError.dataCorrupted(context) {
            throw FoldLintError.invalidConfiguration(path: path, reason: context.debugDescription)
        } catch let DecodingError.typeMismatch(_, context) {
            throw FoldLintError.invalidConfiguration(path: path, reason: "wrong type for \(context.codingPath.map(\.stringValue).joined(separator: "."))")
        } catch let DecodingError.valueNotFound(_, context) {
            throw FoldLintError.invalidConfiguration(path: path, reason: "missing value for \(context.codingPath.map(\.stringValue).joined(separator: "."))")
        } catch {
            throw FoldLintError.invalidConfiguration(path: path, reason: "not valid JSON")
        }
    }

    /// Keys in a config file that FoldLint doesn't recognize (likely typos).
    public static func unknownKeys(in path: String) -> [String] {
        guard let data = FileManager.default.contents(atPath: path),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }
        let known = Set(["disabled_rules", "only_rules", "excluded", "severity", "fail_on", "min_score"])
        return object.keys.filter { !known.contains($0) }.sorted()
    }

    /// Rule IDs referenced by this configuration that don't exist.
    public var unknownRuleIDs: [String] {
        let known = Set(RuleRegistry.all.map(\.id))
        let referenced = disabledRules + (onlyRules ?? []) + Array(severity.keys)
        return Array(Set(referenced.filter { !known.contains($0) })).sorted()
    }

    /// Looks for `.foldlint.json` in the given directory.
    public static func discover(in directory: String) throws -> Configuration? {
        let path = (directory as NSString).appendingPathComponent(defaultFileName)
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        return try load(from: path)
    }

    public func isEnabled(_ ruleID: String) -> Bool {
        if let onlyRules, !onlyRules.contains(ruleID) { return false }
        return !disabledRules.contains(ruleID)
    }
}
