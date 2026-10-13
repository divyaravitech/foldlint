import Foundation

/// Computes stable fingerprints for findings.
///
/// A fingerprint hashes the rule ID, the file path and the *trimmed text* of the flagged
/// line, plus an occurrence index for identical lines in the same file. It does not
/// include the line number, so adding or removing code above a finding doesn't change it.
enum Fingerprinter {
    static func assign(to findings: [Finding], sources: [String: [Substring]]) -> [Finding] {
        var occurrences: [String: Int] = [:]
        return findings.map { finding in
            let lineText: String
            if let lines = sources[finding.file], finding.line >= 1, finding.line <= lines.count {
                lineText = lines[finding.line - 1].trimmingCharacters(in: .whitespacesAndNewlines)
            } else {
                lineText = ""
            }
            let key = "\(finding.ruleID)|\(finding.file)|\(lineText)"
            let occurrence = occurrences[key, default: 0]
            occurrences[key] = occurrence + 1
            var copy = finding
            copy.fingerprint = hex(fnv1a64("\(key)|\(occurrence)"))
            return copy
        }
    }

    /// 64-bit FNV-1a. Stable across runs, platforms and Swift versions (unlike `Hasher`).
    static func fnv1a64(_ string: String) -> UInt64 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return hash
    }

    private static func hex(_ value: UInt64) -> String {
        let digits = String(value, radix: 16)
        return String(repeating: "0", count: 16 - digits.count) + digits
    }
}

/// A set of known findings to ignore, so CI can fail on *new* problems only.
///
/// ```json
/// { "version": 1, "tool": "foldlint", "fingerprints": ["1f3a…", "…"] }
/// ```
public struct Baseline: Codable, Equatable {
    public static let currentVersion = 1

    public let version: Int
    public let tool: String
    public let fingerprints: [String]
    private let lookup: Set<String>

    enum CodingKeys: String, CodingKey {
        case version, tool, fingerprints
    }

    public init(fingerprints: [String]) {
        let unique = Set(fingerprints)
        self.version = Baseline.currentVersion
        self.tool = "foldlint"
        self.fingerprints = unique.sorted()
        self.lookup = unique
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(Int.self, forKey: .version)
        tool = try container.decodeIfPresent(String.self, forKey: .tool) ?? "foldlint"
        fingerprints = try container.decode([String].self, forKey: .fingerprints)
        lookup = Set(fingerprints)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(version, forKey: .version)
        try container.encode(tool, forKey: .tool)
        try container.encode(fingerprints, forKey: .fingerprints)
    }

    public func contains(_ finding: Finding) -> Bool {
        lookup.contains(finding.fingerprint)
    }

    public static func load(from path: String) throws -> Baseline {
        let data: Data
        do {
            data = try Data(contentsOf: URL(fileURLWithPath: path))
        } catch {
            throw FoldLintError.invalidBaseline(path: path, reason: "file could not be read")
        }
        let baseline: Baseline
        do {
            baseline = try JSONDecoder().decode(Baseline.self, from: data)
        } catch {
            throw FoldLintError.invalidBaseline(path: path, reason: "not valid baseline JSON")
        }
        guard baseline.version == currentVersion else {
            throw FoldLintError.invalidBaseline(path: path, reason: "unsupported version \(baseline.version)")
        }
        return baseline
    }

    public func write(to path: String) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        var data = try encoder.encode(self)
        data.append(0x0A)
        try data.write(to: URL(fileURLWithPath: path), options: .atomic)
    }
}
