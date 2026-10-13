# FoldLint

**A static analyzer that tells you whether your Swift app is ready for iPhone Duo.**

[![CI](https://github.com/divyaravitech/foldlint/actions/workflows/ci.yml/badge.svg)](https://github.com/divyaravitech/foldlint/actions/workflows/ci.yml)
[![Swift 6.0+](https://img.shields.io/badge/Swift-6.0%2B-orange.svg)](https://swift.org)
[![Platforms](https://img.shields.io/badge/platforms-macOS%20%7C%20Linux-lightgrey.svg)](#install)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

iPhone Duo has two displays, a hinge, toolbars that move to the side, and front cameras that can face away from the user. Code that has worked on every iPhone so far, such as `UIScreen.main`, `userInterfaceIdiom == .pad`, a hand-built `UIToolbar()` or `camera.position == .front`, now produces the wrong layout or, in one case, crashes.

FoldLint finds that code with a SwiftSyntax-based analysis. It explains each fix and cites the Apple documentation the rule is based on, then scores your project from 0 to 100.

```text
$ foldlint Examples/BeforeDuo

Examples/BeforeDuo/AppDelegate.swift:4:13: error: This app hasn't adopted the UIScene lifecycle. Per TN3187, apps built with the SDK after iOS 26 won't launch without it, and iPhone Duo's multiple windows depend on it. [scene-lifecycle]
    fix: Add a UIWindowSceneDelegate plus a UIApplicationSceneManifest (or implement application(_:configurationForConnecting:options:)), or use the SwiftUI App lifecycle.
Examples/BeforeDuo/CameraController.swift:7:28: error: The inner and outer ultra wide cameras can only be discovered with AVCaptureDevice.DiscoverySession; AVCaptureDevice.default(_:for:position:) won't return them. [camera-discovery]
    fix: Use AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInOuterUltraWideCamera, .builtInInnerUltraWideCamera], mediaType: .video, position: .unspecified).
Examples/BeforeDuo/CameraController.swift:12:13: error: Assigning isVideoMirrored raises an exception while automaticallyAdjustsVideoMirroring is true. On iPhone Duo, apps override mirroring whenever a camera's position and direction disagree. [video-mirroring]
    fix: Check connection.isVideoMirroringSupported, set automaticallyAdjustsVideoMirroring = false, then assign isVideoMirrored.
Examples/BeforeDuo/FeedViewController.swift:14:21: warning: UIScreen.main is deprecated (iOS 26) and ambiguous on iPhone Duo, which has two displays. [uiscreen-main]
    fix: Use the trait collection (traitCollection.displayScale, @Environment(\.displayScale)), view or scene bounds, or view.window?.windowScene?.screen.
Examples/BeforeDuo/PlayerView.swift:7:17: warning: NavigationStack inside ArrangementView: arrangements don't handle navigation, so keep navigation containers outside them. [navigation-inside-arrangement]
    fix: Wrap the ArrangementView in NavigationStack/NavigationSplitView/TabView instead of nesting them inside.
…

iPhone Duo readiness: 35/100 · Not Ready
███████████░░░░░░░░░░░░░░░░░░░
3 errors · 9 warnings · 3 notes · 4 files scanned
Top issues: text-only-bar-item (2), uiscreen-main (2), app-wide-window (1)
```

The `file:line:col: warning:` format shows up inline in Xcode when you run FoldLint as a build phase.

## Why FoldLint

- **Cites its sources.** All 15 rules come from Apple's iPhone Duo tech talks, the Human Interface Guidelines, API reference pages or technotes, and [docs/rules.md](docs/rules.md) links each one.
- **Low noise by design.** The analysis is syntax-aware, so comments and strings are ignored and nesting rules understand structure. When a rule can't be sure, it stays quiet: for example, it doesn't flag `position: .front` discovery, which Apple says is still correct.
- **Built for adoption in large codebases.** Baselines let CI fail only on new findings, fingerprints stay stable when code moves, and suppressions work per line or per file.
- **Fast.** Files are parsed in parallel. It analyzes swift-syntax's own 752 files (295k lines) in about 2 seconds on a 2-core Linux VM.
- **Fits your workflow.** Output formats are Xcode text, JSON, GitHub annotations, SARIF 2.1.0 (code scanning) and Markdown (PR comments and job summaries). It also runs as a SwiftPM plugin and a GitHub Action, and ships a SwiftLint rule pack.
- **Readiness score and badge** for tracking migration progress.

## Install

**Mint**

```sh
mint install divyaravitech/foldlint
```

**From source** (macOS 13+ with Xcode 16+, or Linux with Swift 6.0+)

```sh
git clone https://github.com/divyaravitech/foldlint
cd foldlint && swift build -c release
cp .build/release/foldlint /usr/local/bin/
```

**SwiftPM plugin**: add FoldLint as a package dependency, then run:

```sh
swift package foldlint                # lints the package
swift package foldlint --format json  # any CLI option works
```

**Homebrew**: planned (see [RELEASING.md](RELEASING.md)).

## Usage

```sh
foldlint                                   # lint the current directory
foldlint Sources App/Info.plist            # lint specific paths
foldlint --format sarif -o foldlint.sarif  # text | json | github | sarif | markdown
foldlint --fail-on warning                 # fail on warnings too (default: error)
foldlint --min-score 80                    # fail if the readiness score drops below 80
foldlint --write-baseline .foldlint-baseline.json   # accept today's findings…
foldlint --baseline .foldlint-baseline.json         # …and fail CI only on new ones
foldlint --badge .github/duo-badge.json    # write a shields.io endpoint badge
foldlint --disable orientation-lock text-only-bar-item
foldlint --list-rules [--format json]
```

| Exit code | Meaning |
| --- | --- |
| `0` | Passed |
| `1` | Findings at or above `--fail-on`, or score below `--min-score` |
| `64` | Usage or configuration error |

### Xcode build phase

Add a Run Script phase so findings appear inline as warnings:

```sh
if command -v foldlint >/dev/null; then
  foldlint "$SRCROOT" --fail-on never
fi
```

### GitHub Action

```yaml
- uses: divyaravitech/foldlint@v0
  with:
    path: .
    fail-on: error
    min-score: 80                         # optional
    baseline: .foldlint-baseline.json     # optional
    sarif: foldlint.sarif                 # optional, for code scanning
```

The action runs on macOS and Linux runners. Each finding becomes an inline PR annotation, the job summary gets a score table, and the `score` output is available to later steps.

### SwiftLint

Copy the `custom_rules` from [`swiftlint/duo-rules.yml`](swiftlint/duo-rules.yml) into your `.swiftlint.yml`. You get 9 regex-only checks. The syntax-aware rules, baselines and the score are available only in FoldLint itself.

## Rules

| Rule | Default | What it catches |
| --- | --- | --- |
| `uiscreen-main` | ⚠️ | `UIScreen.main`, which is deprecated in iOS 26 and ambiguous with two displays |
| `screen-bounds-layout` | ⚠️ | Sizing from `screen.bounds` |
| `idiom-branching` | ⚠️ | `userInterfaceIdiom` checks; Duo is `.phone` with a regular-width inner display |
| `orientation-branching` | ⚠️ | Layout driven by interface or device orientation |
| `orientation-lock` | ℹ️ | Orientation locks, which the inner display doesn't honor |
| `standalone-bar` | ⚠️ | `UIToolbar()` and similar bars, which don't move to the vertical axis |
| `text-only-bar-item` | ℹ️ | Toolbar items with no symbol |
| `arrangement-in-scroll` | ⚠️ | `ArrangementView` inside `List` or `ScrollView` |
| `navigation-inside-arrangement` | ⚠️ | `NavigationStack` or `TabView` inside `ArrangementView` |
| `app-wide-window` | ⚠️ | `UIApplication.shared.keyWindow`, `.windows`, `.connectedScenes.first` |
| `video-mirroring` | ⛔ | `isVideoMirrored =` while automatic mirroring is on, which raises an exception |
| `front-camera-assumption` | ⚠️ | `position == .front`, which says where a camera sits, not which way it faces |
| `camera-discovery` | ⛔ | Duo's individual cameras requested via `default(_:for:position:)`, which returns `nil` |
| `requires-full-screen` | ℹ️ | `UIRequiresFullScreen`, which doesn't prevent resizing on Duo |
| `scene-lifecycle` | ⛔ | No UIScene lifecycle, which TN3187 says will stop apps launching |

Each rule is documented in **[docs/rules.md](docs/rules.md)** with ❌ and ✅ examples and its Apple source.

## Configuration

Create `.foldlint.json` in the directory you run FoldLint from. Every key is optional:

```json
{
  "disabled_rules": ["orientation-lock"],
  "only_rules": null,
  "excluded": ["Vendor", "Generated"],
  "severity": { "text-only-bar-item": "warning" },
  "fail_on": "error",
  "min_score": 80
}
```

Unknown keys and rule IDs produce warnings, so typos don't fail silently. `Pods`, `Carthage`, `.build`, `DerivedData`, `build`, `node_modules`, `fastlane` and hidden folders are always excluded.

### Suppressions

```swift
// foldlint:disable-next-line uiscreen-main
let scale = UIScreen.main.scale

let width = window.screen.bounds.width // foldlint:disable-line

// foldlint:disable-file idiom-branching
```

### Baselines

A baseline records today's findings so CI can **fail only on new ones**. This lets a large codebase adopt FoldLint without fixing everything first. Each finding's fingerprint hashes the rule, file and the trimmed source line, but not the line number, so the baseline survives unrelated edits. Baselined findings still count toward the score, so the debt stays visible.

## The readiness score

Each rule has a weight from 2 to 10. A rule with no findings earns its full weight. The first finding costs 70% of it, and each further finding halves what's left:

```
credit(rule) = findings == 0 ? weight : weight × 0.3 × 0.5^(findings − 1)
score        = round(100 × Σ credit / Σ weight)
```

So the score mostly reflects **how many kinds** of problem you have. That tracks migration effort better than the raw number of occurrences.

| Score | Grade |
| --- | --- |
| 90–100 | 🟢 Duo Ready |
| 70–89 | 🟡 Almost Ready |
| 40–69 | 🟠 Needs Work |
| 0–39 | 🔴 Not Ready |

To show the score in your README, generate a badge file:

```sh
foldlint --badge .github/duo-badge.json
```

Commit the file, then add:

```markdown
![iPhone Duo ready](https://img.shields.io/endpoint?url=https://raw.githubusercontent.com/OWNER/REPO/main/.github/duo-badge.json)
```

## Before and after

[`Examples/BeforeDuo`](Examples/BeforeDuo) breaks every rule family and scores 35. [`Examples/AfterDuo`](Examples/AfterDuo) is the same app fixed, including Apple's direction-coordinator camera pattern, and scores **100**. Diffing the two folders is a quick tour of the migration.

## How it works

See [docs/architecture.md](docs/architecture.md) for the pipeline, the design decisions (why SwiftSyntax, why fingerprints skip line numbers, why the score is shaped this way) and the extension points.

## Roadmap

- [ ] Homebrew formula and prebuilt universal binaries
- [ ] `--fix` for mechanical rewrites (`UIScreen.main.scale` → `traitCollection.displayScale`)
- [ ] Xcode build-tool plugin for `.xcodeproj` targets
- [ ] Objective-C support
- [ ] Rules for `reservedRegions` adoption and hinge-driven layout

## Contributing

New rules are the best first contribution: each one is about 15 lines plus tests. See [CONTRIBUTING.md](CONTRIBUTING.md). For a curated list of iPhone Duo resources, see [awesome-iphone-duo](https://github.com/divyaravitech/awesome-iphone-duo).

---

*FoldLint is a community project and isn't affiliated with Apple. iPhone Duo APIs are new and may change; if a rule falls out of date with the SDK, please open an issue.*
