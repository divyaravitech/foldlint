# Contributing to FoldLint

Thanks for helping iOS teams get ready for iPhone Duo. New rules, fewer false positives and better docs are all welcome.

## Setup

```sh
git clone https://github.com/divyaravitech/foldlint && cd foldlint
swift test
swift run foldlint Examples/BeforeDuo
```

You need Swift 6.0 or later: Xcode 16+ on macOS 13+, or a Swift 6 toolchain on Linux (`docker run -it -v $PWD:/src -w /src swift:6.0 swift test` works too).

## Adding a rule in about 15 minutes

1. **Write the test first** in `Tests/FoldLintCoreTests/RuleTests.swift`. Add at least one snippet that should be flagged and one that should not:

   ```swift
   func testMyRuleFlagged() {
       XCTAssertEqual(ids("let x = Bad.thing"), ["my-rule"])
   }
   func testMyRuleNotFlagged() {
       XCTAssertEqual(ids("let x = Good.thing"), [])
   }
   ```

2. **Implement it** in the matching file under `Sources/FoldLintCore/Rules/`. Most rules take about 15 lines:

   ```swift
   public struct MyRule: SwiftRule {
       public init() {}
       public let descriptor = RuleDescriptor(
           id: "my-rule", name: "My rule", severity: .warning, weight: 5,
           summary: "What breaks on iPhone Duo and why.",
           fix: "What to do instead.",
           reference: "\(RuleRegistry.docsBase)#my-rule"
       )
       public func check(_ file: SwiftFile) -> [Finding] {
           file.nodes(MemberAccessExprSyntax.self).compactMap { node in
               guard node.memberName == "thing" else { return nil }
               let loc = file.location(of: node)
               return descriptor.finding(file: file.path, line: loc.line, column: loc.column)
           }
       }
   }
   ```

   Useful helpers: `file.nodes(T.self)` (cached; the tree is walked once per file), `call.calleeName`, `call.enclosingCalls()`, `member.normalizedBase`. See [docs/architecture.md](docs/architecture.md) for the pipeline.

3. **Register it** in `RuleRegistry` (in `Rule.swift`).
4. **Document it**: add a `## my-rule` section to `docs/rules.md` with *why*, a ❌ example, a ✅ example and an Apple source, and add a row to the README's rules table. `CoreBehaviorTests.testEveryRuleIsDocumented` fails until you do.
5. If it can be expressed as a regex, add it to `swiftlint/duo-rules.yml` with fixtures in `scripts/check_swiftlint_pack.py`.
6. Run `swift test` (and `python3 scripts/check_swiftlint_pack.py` if you touched the pack), update `CHANGELOG.md`, and open a PR.

## Rule guidelines

- **Cite Apple.** Every rule should link to an API reference page, an article, a technote, the HIG or a tech talk. Prefer reference pages over videos, because they're versioned and searchable.
- **Match spelling, not types.** FoldLint doesn't type-check, so a rule sees `position == .front`, not "an `AVCaptureDevice.Position`". Design matches so that a false positive is unlikely, and add a negative test for the closest look-alike.
- **Prefer false negatives to false positives.** A noisy linter gets uninstalled.
- **Weights:** use 10 for "will look broken or crash", 6–8 for "visibly wrong layout", and 2–4 for advice.
- Rule IDs are kebab-case and never change once released.

## Good first issues

Look for the [`good first issue`](https://github.com/divyaravitech/foldlint/labels/good%20first%20issue) label. Rule proposals are tagged that way automatically.
