# Architecture

FoldLint is a small, dependency-light static analyzer. This document explains how it's put together and why, so contributors can change it confidently.

## Pipeline

```
paths ──► FileDiscovery ──► .swift files ──(parallel)──► SwiftFile (parse once, index once)
                     │                                         │
                     │                                         ├─► SwiftRule × N ─► Suppressions ─► findings
                     │                                         └─► FactCollector ─► ProjectFacts (per file)
                     └─► Info.plist files ──► PlistRule × N ──► findings, facts
                                                                       │
                       ProjectFacts (merged) ──► ProjectRule × N ──► findings
                                                                       │
                severity overrides ─► sort ─► Fingerprinter ─► ReadinessScore ─► Baseline filter ─► Reporter
```

| Stage | Type | Notes |
| --- | --- | --- |
| Discovery | `FileDiscovery` | Walks the paths, skips hidden folders and `excluded`, and returns sorted file lists, so output is deterministic. |
| Parsing | `SwiftFile` | Parses each file with `SwiftParser` once, collects every node in a single walk, and caches per-type views (`nodes(_:)`). |
| Rules | `SwiftRule`, `PlistRule`, `ProjectRule` | Pure functions from input to `[Finding]`. They hold no state, so running them in parallel is safe. |
| Facts | `FactCollector`, `ProjectFacts` | Cross-file information, such as "is there a scene delegate anywhere?", gathered per file and merged. |
| Suppressions | `Suppressions` | `foldlint:disable-line`, `disable-next-line` and `disable-file`, applied per file before results leave the worker. |
| Fingerprints | `Fingerprinter` | `FNV-1a(rule | file | trimmed line text | occurrence)`, as 16 hex digits. |
| Score | `ReadinessScore` | A weighted score per rule; see the README. |
| Baseline | `Baseline` | A set of fingerprints. It filters what is *reported*, not what is *scored*. |
| Output | `Reporter` | Text (Xcode-compatible), JSON, GitHub workflow commands, SARIF 2.1.0 and Markdown. |

## Design decisions

**SwiftSyntax rather than regexes.** Several rules depend on structure (`ArrangementView` *inside* `List`, a `Button` *inside* `.toolbar` but *not inside* a `Menu`), and every rule must ignore comments and strings. A regex can do neither reliably. The SwiftLint pack exists for teams that want a regex subset, and it says what it can't check.

**Syntax, not types.** FoldLint doesn't type-check. That keeps it fast and buildable on Linux without an SDK, and lets it run on code that doesn't compile yet. The cost is that rules match on spelling (for example `position == .front`), so each rule is designed to prefer false negatives to false positives. See `CONTRIBUTING.md`.

**Parse once, walk once.** Each file is parsed once and walked once. Rules query the cached node lists, so adding a rule costs a filter, not another tree traversal. Files are processed with `DispatchQueue.concurrentPerform`. Results go into a pre-sized buffer by index, and the output is sorted, so it's identical across runs (`CoreBehaviorTests.testParallelLintingIsDeterministic`).

**Fingerprints ignore line numbers.** A baseline must survive unrelated edits above a finding. Hashing the trimmed line text, rather than its position, achieves that. An occurrence counter keeps identical lines in one file distinct. FNV-1a is used instead of `Hasher`, because `Hasher` is randomly seeded per process. A test pins the hash values so baselines don't silently break.

**Baselines filter reporting, not scoring.** Teams adopt a baseline to stop new regressions, not to pretend existing ones are gone. The score keeps counting baselined findings.

**Score shape.** The first finding costs 70% of a rule's weight, and each later one halves what's left. This makes the score track *breadth* (how many kinds of problem), which correlates with migration effort, and stops one file with 400 `UIScreen.main` calls from dominating.

## Adding things

- **A rule:** see `CONTRIBUTING.md`. Register it in `RuleRegistry`. `CoreBehaviorTests` fails until the rule is documented in `docs/rules.md` and listed in the README.
- **An output format:** add a case to `OutputFormat` and a renderer in `Reporter`. The CLI picks it up automatically.
- **A cross-file rule:** add a field to `ProjectFacts` and its `merge(_:)`, populate it in `FactCollector`, and implement `ProjectRule`.

## Non-goals

- Type-aware analysis (use the compiler or SourceKit-based tools for that).
- Runtime checks. Fold, hinge and camera direction behavior needs a device or Device Hub.
- Objective-C (planned, but as a separate front end).
