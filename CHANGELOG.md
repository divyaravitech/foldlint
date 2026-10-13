# Changelog

All notable changes to this project are documented here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses [Semantic Versioning](https://semver.org/).

## [Unreleased]

## [0.1.0]

### Added

- 15 rules covering layout, vertical bars, `ArrangementView`, windows and scenes, cameras, Info.plist and the UIScene lifecycle. Each rule cites its Apple source in `docs/rules.md`.
- iPhone Duo readiness score (0–100), with a shields.io badge.
- Output formats: Xcode-compatible text, JSON, GitHub annotations, SARIF 2.1.0 with `partialFingerprints`, and Markdown.
- Baselines (`--write-baseline`, `--baseline`) with line-shift-stable fingerprints.
- `.foldlint.json` configuration with warnings for unknown keys and rule IDs, plus `// foldlint:disable-…` suppressions.
- Parallel analysis; deterministic output.
- SwiftPM command plugin (`swift package foldlint`), GitHub Action, and a 9-rule SwiftLint `custom_rules` pack.
- macOS and Linux support.
