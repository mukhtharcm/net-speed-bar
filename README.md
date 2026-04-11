# Net Speed Bar

Net Speed Bar is a lightweight macOS menu bar app that shows your current download and upload speed live in the menu bar.

## Features

- Live download and upload speed in the menu bar
- Popover with larger speed cards and connection details
- Latency monitor with configurable ping target
- Historical bandwidth usage with bar charts (daily / weekly / monthly)
- Threshold alerts with system notifications
- Session totals, peak speed tracking, sparkline chart
- Bits or bytes display toggle
- Configurable refresh interval and launch at login
- Small, menu-bar-only app with no Dock icon

## Install

### Homebrew

```sh
brew install --cask mukhtharcm/tap/net-speed-bar
```

### Manual Download

Download the latest `.dmg` or `.zip` from [Releases](https://github.com/mukhtharcm/net-speed-bar/releases), move `Net Speed Bar.app` to `Applications`, and launch it.

## Usage

- The menu bar shows your current network speed live.
- Click the menu bar item to open the popover.
- Press `Quit` in the popover when you want to close the app.

## Notes

- Wi-Fi name display may not always be available on macOS.
- Speed values are based on active network interface traffic and refresh continuously.
