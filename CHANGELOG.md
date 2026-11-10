# Changelog — ImageDrop
by deepquest | https://deepquest.code511.com/blog

All notable changes are listed here. Versions follow [Semantic Versioning](https://semver.org): MAJOR.MINOR.PATCH.
The current version is in `VERSION`; the build number (`BUILD`) goes up by one with every delivered revision.

## [1.2.4] — 2026-11-10 (build 8)
### Added
- App screenshot in the README (`docs/screenshot.webp`, 14.7 KB).
### Changed
- The build workflow is now in the repo, so every new `VERSION` is built and published to GitHub Releases automatically. v1.2.3 was the first automatic release.

## [1.2.3] — 2026-11-09 (build 7)
### Removed
- `publish.sh`. It was only needed for the first publish; the repo now lives at https://github.com/deepquest-io/ImageDrop.
### Changed
- README project layout updated to match.

## [1.2.2] — 2026-11-09 (build 6)
### Changed
- First version published on GitHub: https://github.com/deepquest-io/ImageDrop
- Scripts are now run with `bash build.sh` / `bash publish.sh` (in the README and CI), so they work even when a download loses the executable flag.

## [1.2.1] — 2026-11-09 (build 5)
### Added
- `tools/make-icon.swift` draws the app icon in code. `build.sh` uses it when `Resources/AppIcon.icns` is missing (e.g. in a fresh git clone), so the repo needs no binary files.
- Automatic releases: pushing to `main` with a `VERSION` that hasn't been released yet builds the app, creates the `vX.Y.Z` tag and publishes the GitHub Release. Pushing a tag yourself still works.
### Changed
- README links and badges now point to `github.com/deepquest-io/ImageDrop`.
- `build.sh` still builds if the icon can't be generated (it falls back to the default icon).

## [1.2.0] — 2026-11-09 (build 4)
### Added
- Everything needed to publish on GitHub:
  - `publish.sh`: creates the GitHub repo, pushes the code, adds topics and tags the version (uses the `gh` CLI).
  - GitHub Actions workflow (`.github/workflows/build.yml`): builds the app on every push and pull request; pushing a `vX.Y.Z` tag builds a universal (arm64 + x86_64) app and publishes it as a GitHub Release, using this changelog for the release notes.
  - `LICENSE` (MIT, © 2026 deepquest) and `.gitignore`. The app is free and open source; the only requirement for using or forking it is keeping the deepquest credit.
### Changed
- README rewritten for GitHub: badges, a Download section with first-launch (Gatekeeper) steps, build-from-source steps, how to release a new version, and the license.

## [1.1.0] — 2026-11-09 (build 3)
### Added
- Credits for deepquest | https://deepquest.code511.com/blog:
  - About ImageDrop window with a link you can click
  - "by deepquest" link in the window footer
  - Help menu → "deepquest Blog"
  - Copyright shown in Finder's Get Info (`NSHumanReadableCopyright`)
  - Credit header in every source file, plus a credits section in the README
- `CHANGELOG.md`, `VERSION` and `BUILD` files. `build.sh` now reads the version and build number from them.
### Changed
- Bundle identifier changed to `com.code511.deepquest.imagedrop`.
- The zip and folder names now include the version.

## [1.0.1] — 2026-11-09 (build 2)
### Fixed
- Build error: `WebPConfig` has no member `alpha_filter`. Renamed it to `alpha_filtering`.

## [1.0.0] — 2026-11-09 (build 1)
### Added
- First release: a native SwiftUI drag-and-drop image converter for macOS 13+.
- Drop images or folders on the window or the Dock icon; several files convert at once.
- Output formats: WebP (bundled libwebp), JPEG, PNG, HEIC, AVIF (when macOS can write it), TIFF, GIF, BMP, JPEG 2000.
- Tuned WebP settings: method 6, sharp YUV, photo preset for camera sources, and Smart, Lossy and Lossless modes.
- Settings for quality, max size, keeping metadata and output folder. Settings are remembered.
- Never overwrites files: names get a `-1`, `-2`, … suffix when taken.
- `build.sh` builds the `.app`, with `--install` and `--universal` options.
