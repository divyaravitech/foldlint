import Foundation

/// The result of linting a project.
public struct LintResult {
    /// Findings to report, after suppressions and the baseline (if any) are applied.
    public let findings: [Finding]
    /// Number of findings hidden because they appear in the baseline.
    public let baselinedCount: Int
    /// Fingerprints of every finding before the baseline was applied (used by `--write-baseline`).
    public let allFingerprints: [String]
    public let filesScanned: Int
    public let rules: [RuleDescriptor]
    /// The readiness score. It counts *all* findings, including baselined ones,
    /// so a baseline gates new regressions without hiding existing debt.
    public let score: ReadinessScore
    /// Non-fatal problems, such as unreadable files.
    public let warnings: [String]
}

/// Runs the enabled rules over files and applies suppressions, severity overrides and baselines.
///
/// `Linter` is a value type with no mutable state, and is safe to use from multiple threads.
public struct Linter {
    public let configuration: Configuration
    public let baseline: Baseline?

    public init(configuration: Configuration = Configuration(), baseline: Baseline? = nil) {
        self.configuration = configuration
        self.baseline = baseline
    }

    public var enabledRules: [RuleDescriptor] {
        RuleRegistry.all
            .filter { configuration.isEnabled($0.id) }
            .map { withSeverityOverride(rule: $0) }
    }

    // MARK: Public entry points

    /// Lints files and directories on disk. Swift files are parsed and checked in parallel.
    public func lint(paths: [String]) throws -> LintResult {
        let files = try FileDiscovery(excluded: configuration.excluded).collect(paths: paths)

        // 1. Per-file Swift rules, in parallel. Each slot is written by exactly one iteration.
        let results = ConcurrentResults<FileOutcome>(count: files.swift.count)
        DispatchQueue.concurrentPerform(iterations: files.swift.count) { index in
            results[index] = lintSwiftFile(atPath: files.swift[index])
        }

        var findings: [Finding] = []
        var facts = ProjectFacts()
        var warnings: [String] = []
        var sources: [String: [Substring]] = [:]
        for outcome in results.values {
            switch outcome {
            case .linted(let path, let lines, let fileFindings, let fileFacts):
                findings += fileFindings
                facts.merge(fileFacts)
                sources[path] = lines
            case .unreadable(let path, let reason):
                warnings.append("Skipped \(path): \(reason)")
            case .none:
                break
            }
        }

        // 2. Info.plist rules.
        for path in files.plists {
            guard let data = FileManager.default.contents(atPath: path),
                  let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
            else {
                warnings.append("Skipped \(path): not a readable property list")
                continue
            }
            if plist["UIApplicationSceneManifest"] != nil {
                facts.plistDeclaresSceneManifest = true
            }
            for rule in RuleRegistry.plistRules where configuration.isEnabled(rule.descriptor.id) {
                findings += rule.check(path: path, plist: plist)
            }
        }

        // 3. Project-wide rules.
        for rule in RuleRegistry.projectRules where configuration.isEnabled(rule.descriptor.id) {
            findings += rule.check(facts)
        }

        findings = Fingerprinter.assign(
            to: findings.map { withSeverityOverride(finding: $0) }.sorted(by: Self.order),
            sources: sources
        )
        let rules = enabledRules
        let score = ReadinessScore(findings: findings, rules: rules)
        let reported = baseline.map { baseline in findings.filter { !baseline.contains($0) } } ?? findings

        return LintResult(
            findings: reported,
            baselinedCount: findings.count - reported.count,
            allFingerprints: findings.map(\.fingerprint),
            filesScanned: files.swift.count + files.plists.count,
            rules: rules,
            score: score,
            warnings: warnings
        )
    }

    /// Lints a single in-memory Swift source. Only per-file Swift rules run. Handy for tests and editors.
    public func lint(source: String, path: String = "Input.swift") -> [Finding] {
        let findings = lint(file: SwiftFile(path: path, source: source))
            .map { withSeverityOverride(finding: $0) }
            .sorted(by: Self.order)
        return Fingerprinter.assign(to: findings, sources: [path: source.split(separator: "\n", omittingEmptySubsequences: false)])
    }

    // MARK: Internals

    enum FileOutcome {
        case linted(path: String, lines: [Substring], findings: [Finding], facts: ProjectFacts)
        case unreadable(path: String, reason: String)
    }

    private func lintSwiftFile(atPath path: String) -> FileOutcome {
        let source: String
        do {
            source = try String(contentsOfFile: path, encoding: .utf8)
        } catch {
            return .unreadable(path: path, reason: "not valid UTF-8 or not readable")
        }
        let file = SwiftFile(path: path, source: source)
        var facts = ProjectFacts()
        FactCollector.collect(from: file, into: &facts)
        return .linted(
            path: path,
            lines: source.split(separator: "\n", omittingEmptySubsequences: false),
            findings: lint(file: file),
            facts: facts
        )
    }

    func lint(file: SwiftFile) -> [Finding] {
        let suppressions = Suppressions(source: file.source)
        var findings: [Finding] = []
        for rule in RuleRegistry.swiftRules where configuration.isEnabled(rule.descriptor.id) {
            findings += rule.check(file).filter { !suppressions.isSuppressed($0) }
        }
        return findings
    }

    private func withSeverityOverride(finding: Finding) -> Finding {
        guard let severity = configuration.severity[finding.ruleID] else { return finding }
        var copy = finding
        copy.severity = severity
        return copy
    }

    private func withSeverityOverride(rule: RuleDescriptor) -> RuleDescriptor {
        guard let severity = configuration.severity[rule.id] else { return rule }
        return RuleDescriptor(
            id: rule.id, name: rule.name, severity: severity, weight: rule.weight,
            summary: rule.summary, fix: rule.fix, reference: rule.reference
        )
    }

    static func order(_ lhs: Finding, _ rhs: Finding) -> Bool {
        (lhs.file, lhs.line, lhs.column, lhs.ruleID) < (rhs.file, rhs.line, rhs.column, rhs.ruleID)
    }
}

/// A fixed-size, lock-protected result buffer for `DispatchQueue.concurrentPerform`.
final class ConcurrentResults<Value> {
    private var storage: [Value?]
    private let lock = NSLock()

    init(count: Int) {
        storage = Array(repeating: nil, count: count)
    }

    subscript(index: Int) -> Value? {
        get { lock.lock(); defer { lock.unlock() }; return storage[index] }
        set { lock.lock(); defer { lock.unlock() }; storage[index] = newValue }
    }

    var values: [Value?] {
        lock.lock(); defer { lock.unlock() }
        return storage
    }
}

// MARK: - Suppressions

/// Supports these comments:
///
///     // foldlint:disable-file uiscreen-main, idiom-branching
///     // foldlint:disable-next-line uiscreen-main
///     let x = UIScreen.main.scale // foldlint:disable-line
///
/// With no rule IDs, the comment suppresses every rule.
struct Suppressions {
    private var fileWide: Set<String> = []
    private var fileWideAll = false
    private var byLine: [Int: Set<String>] = [:]
    private var allOnLine: Set<Int> = []

    private static let directives: [(name: String, lineOffset: Int?)] = [
        ("foldlint:disable-file", nil),
        ("foldlint:disable-next-line", 1),
        ("foldlint:disable-line", 0),
    ]

    init(source: String) {
        guard source.contains("foldlint:") else { return }
        for (index, line) in source.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            for directive in Self.directives {
                guard let range = line.range(of: directive.name) else { continue }
                let ids = Set(
                    line[range.upperBound...]
                        .split(whereSeparator: { $0 == "," || $0.isWhitespace })
                        .map(String.init)
                        .filter { $0.range(of: "^[a-z][a-z0-9-]*$", options: .regularExpression) != nil }
                )
                guard let offset = directive.lineOffset else {
                    if ids.isEmpty { fileWideAll = true } else { fileWide.formUnion(ids) }
                    continue
                }
                let target = index + 1 + offset
                if ids.isEmpty {
                    allOnLine.insert(target)
                } else {
                    byLine[target, default: []].formUnion(ids)
                }
            }
        }
    }

    func isSuppressed(_ finding: Finding) -> Bool {
        if fileWideAll || fileWide.contains(finding.ruleID) { return true }
        if allOnLine.contains(finding.line) { return true }
        return byLine[finding.line]?.contains(finding.ruleID) ?? false
    }
}

// MARK: - File discovery

struct FileDiscovery {
    let excluded: [String]

    struct Files {
        var swift: [String] = []
        var plists: [String] = []
    }

    func collect(paths: [String]) throws -> Files {
        var files = Files()
        let fm = FileManager.default
        for rawPath in paths {
            let path = Self.normalize(rawPath)
            var isDirectory: ObjCBool = false
            guard fm.fileExists(atPath: path, isDirectory: &isDirectory) else {
                throw FoldLintError.pathNotFound(rawPath)
            }
            if !isDirectory.boolValue {
                add(path, to: &files)
                continue
            }
            guard let enumerator = fm.enumerator(atPath: path) else { continue }
            while let relative = enumerator.nextObject() as? String {
                let name = (relative as NSString).lastPathComponent
                if isExcluded(name, relativePath: relative) {
                    enumerator.skipDescendants()
                    continue
                }
                let full = path == "." ? relative : (path as NSString).appendingPathComponent(relative)
                add(full, to: &files)
            }
        }
        files.swift = Array(Set(files.swift)).sorted()
        files.plists = Array(Set(files.plists)).sorted()
        return files
    }

    private func isExcluded(_ name: String, relativePath: String) -> Bool {
        if name.hasPrefix(".") { return true }
        return excluded.contains { $0 == name || $0 == relativePath || relativePath.hasPrefix($0 + "/") }
    }

    private func add(_ path: String, to files: inout Files) {
        if path.hasSuffix(".swift") {
            files.swift.append(path)
        } else if (path as NSString).lastPathComponent.hasSuffix("Info.plist") {
            files.plists.append(path)
        }
    }

    static func normalize(_ path: String) -> String {
        var result = path
        while result.hasPrefix("./") { result.removeFirst(2) }
        if result.isEmpty { return "." }
        if result.count > 1 && result.hasSuffix("/") { result.removeLast() }
        return result
    }
}

public enum FoldLintError: Error, CustomStringConvertible, Equatable {
    case pathNotFound(String)
    case invalidConfiguration(path: String, reason: String)
    case invalidBaseline(path: String, reason: String)

    public var description: String {
        switch self {
        case .pathNotFound(let path):
            return "No such file or directory: \(path)"
        case .invalidConfiguration(let path, let reason):
            return "Invalid configuration file \(path): \(reason)"
        case .invalidBaseline(let path, let reason):
            return "Invalid baseline file \(path): \(reason)"
        }
    }
}
