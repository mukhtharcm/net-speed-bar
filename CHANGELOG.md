# Changelog

All notable changes to this project will be documented in this file.

## [1.3.0] - 2026-04-11

### Added
- **Historical usage tracking**: bandwidth is now tracked hourly and aggregated into daily summaries, persisted to disk.
- **Usage tab**: new tabbed UI with "Live" and "Usage" views; the Usage tab shows total downloaded/uploaded, a bar chart (hourly or daily), and peak speeds.
- **Period selector**: view usage for Today, 7 Days, or 30 Days.
- Data is retained for 30 days (hourly) and 365 days (daily), with automatic pruning and rollup.

### Fixed
- Latency display in the menu bar now reliably updates (stored `@Published` property instead of computed).

### Changed
- ContentView redesigned with a tab picker at the top.

## [1.2.0] - 2026-04-10

### Added
- **Latency monitor**: live ping measurement using TCP handshake RTT (Cloudflare, Google, or Apple DNS).
- Latency displayed in popover with color-coded status indicator (green/orange/red).
- Optional latency display in the menu bar.
- Settings for latency: enable/disable, ping target selection, show in menu bar.
- **NetSpeedKit library**: extracted testable core logic (traffic reader, speed formatter, latency monitor).
- **75 unit tests** covering traffic snapshots, speed formatting, interface filtering, latency monitor lifecycle, and threshold alerts.

### Changed
- Refactored `Package.swift` into three targets: `MenuBarNetSpeed` (app), `NetSpeedKit` (library), `NetSpeedKitTests` (tests).
- ViewModel delegates all formatting to `SpeedFormatter` for consistency and testability.

## [1.1.1] - 2026-04-10

### Changed
- Renamed the GitHub repository to `net-speed-bar` and updated documentation links.
- Published GitHub release bodies directly from the matching `CHANGELOG.md` entry.
- Added release and changelog documentation for future versioning.

### Fixed
- Fixed traffic speed overcounting by measuring only the main internet-facing interface families.
- Fixed rollover handling in traffic sampling to avoid crashes in `refresh()`.
- Reduced threshold notification noise so alerts only fire when speed crosses above the configured limit.

## [1.1.0] - 2026-04-10

### Changed
- Switched connection detection to a more reliable multi-source approach using `NWPathMonitor` for connectivity and interface type, plus system proxy settings for VPN detection.
- Added clearer connection labels for Wi-Fi, Ethernet, Cellular, and VPN state in the popover.
- Made refresh behavior sleep/wake-aware and added timer tolerance to reduce unnecessary background work.
- Reduced formatter and polling overhead for better efficiency.
- Added release workflow documentation in `RELEASING.md`.

### Fixed
- Fixed notification permission handling when the app bundle identifier is unavailable.
- Stopped incorrectly treating all `.other` network interfaces as VPN connections.

## [1.0.0] - 2026-04-10

### Added
- Redesigned menu bar and popover UI for live download and upload speed.
- Added a settings panel for refresh interval, display mode, network name visibility, and launch at login.
- Added sparkline history, session totals, peak speed tracking, bits-per-second display, and speed threshold alerts.

### Changed
- Improved performance, robustness, and accessibility across the app.
- Redesigned the app icon and simplified DMG packaging.

## [0.1.0-beta.1] - 2026-04-10

### Added
- First prerelease of Net Speed Bar for macOS.
- Automated prerelease publishing through GitHub Actions.
