# Releasing

1. Update `FoldLintVersion.current` in `Sources/FoldLintCore/Model.swift` and move the *Unreleased* notes in `CHANGELOG.md` under the new version.
2. Merge to `main` with CI green.
3. Tag and push:
   ```sh
   git tag v0.1.0 && git push origin v0.1.0
   ```
   `release.yml` checks that the tag matches `FoldLintVersion.current`, builds a universal macOS binary and a static Linux x86_64 binary, and publishes a GitHub release with SHA-256 checksums.
4. Move the floating major tag that GitHub Action users pin to:
   ```sh
   git tag -f v0 && git push -f origin v0
   ```
5. Homebrew (optional): in your tap, update `Formula/foldlint.rb` with the new `url` (the macOS zip) and `sha256` (from the `.sha256` asset).

```ruby
class Foldlint < Formula
  desc "iPhone Duo readiness linter for Swift projects"
  homepage "https://github.com/divyaravitech/foldlint"
  url "https://github.com/divyaravitech/foldlint/releases/download/v0.1.0/foldlint-macos-universal.zip"
  sha256 "REPLACE_WITH_SHA256"
  license "MIT"

  def install
    bin.install "foldlint"
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/foldlint --version")
  end
end
```
