# MenuBarNetSpeed

Small macOS menu bar app that shows live download and upload speed directly in the menu bar using SwiftUI.

## What it does

- Shows current download and upload speed in the menu bar.
- Opens a small popover with larger stats.
- Displays the current Wi-Fi name when macOS exposes it.
- Runs as a menu bar utility without a Dock icon.
- Includes GitHub Actions workflows for CI and tagged releases.

## Run it

```bash
cd MenuBarNetSpeed
swift run
```

If you prefer Xcode, open the `MenuBarNetSpeed` folder as a Swift package project and run the executable target.

## Package a release

```bash
cd MenuBarNetSpeed
./Tools/generate-app-icon.sh
./Tools/package-release.sh
```

This creates a `.app`, `.zip`, and `.dmg` under `dist/<version>/`.

## GitHub automation

- `.github/workflows/ci.yml` builds the package and produces unsigned artifacts on pushes and pull requests.
- `.github/workflows/release.yml` packages and uploads release assets for tags like `v0.1.0`.
- Optional signing and notarization are controlled with GitHub secrets, matching the pattern used in `colleague-clock`.

## Notes

- Speed is calculated from the byte counters on active network interfaces and updates once per second.
- Wi-Fi SSID access may depend on macOS permissions and whether the current connection is actually Wi-Fi.
- Release packaging expects `iconutil`, `ditto`, and the macOS developer tools on the build machine.
