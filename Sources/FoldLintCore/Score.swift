import Foundation

/// An iPhone Duo readiness score from 0 to 100.
///
/// Each enabled rule contributes its `weight`. A clean rule earns its full weight.
/// The first finding costs 70% of it, and each further finding halves what's left:
///
///     credit(rule) = findings == 0 ? weight : weight × 0.3 × 0.5^(findings − 1)
///     score        = round(100 × Σ credit / Σ weight)
///
/// So the score mostly measures how *many kinds* of problem a project has, which
/// tracks migration effort better than the raw number of occurrences.
public struct ReadinessScore: Codable, Equatable {
    public let value: Int
    public let grade: String
    public let countsByRule: [String: Int]

    public init(findings: [Finding], rules: [RuleDescriptor]) {
        var counts: [String: Int] = [:]
        for finding in findings {
            counts[finding.ruleID, default: 0] += 1
        }
        let totalWeight = rules.reduce(0) { $0 + $1.weight }
        let earned = rules.reduce(0.0) { sum, rule in
            let count = counts[rule.id] ?? 0
            let weight = Double(rule.weight)
            return sum + (count == 0 ? weight : weight * 0.3 * pow(0.5, Double(count - 1)))
        }
        let value = totalWeight == 0 ? 100 : Int((100.0 * earned / Double(totalWeight)).rounded())
        self.value = value
        self.grade = ReadinessScore.grade(for: value)
        self.countsByRule = counts
    }

    public static func grade(for value: Int) -> String {
        switch value {
        case 90...: return "Duo Ready"
        case 70..<90: return "Almost Ready"
        case 40..<70: return "Needs Work"
        default: return "Not Ready"
        }
    }

    /// A shields.io color for the badge.
    public var color: String {
        switch value {
        case 90...: return "brightgreen"
        case 70..<90: return "yellowgreen"
        case 40..<70: return "orange"
        default: return "red"
        }
    }
}
