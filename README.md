# Home Assistant for Apple TV

A native tvOS app (SwiftUI, tvOS 17+) for controlling Home Assistant from the couch.

## Features

- **Rooms tab** – every controllable entity grouped by Home Assistant area.
- **Dashboards tab** – your Lovelace dashboards drawn natively (tvOS has no web view), including history graphs, statistics graphs, statistic and sensor cards, entity lists, cameras and markdown. Card types not yet supported show a placeholder; auto-generated and strategy dashboards (e.g. Map) are skipped.
- **Category tabs** – Lights, Climate, Media, Cameras, Security, Scenes and Sensors, shown only when you have matching entities.
- **Live updates** over the WebSocket API, with automatic reconnect.
- **One-click actions** – clicking a tile toggles lights/switches/fans or runs scenes, scripts and buttons. Long-press any tile for details.
- **Detail controls**
  - Lights: on/off, brightness steps and presets, white temperature, colors
  - Climate: target temperature (single or range), HVAC mode, presets, fan mode
  - Media players: artwork, play/pause/skip, volume, mute, power, source
  - Covers/valves, locks, alarm panels (with code entry), vacuums, fans
- **Top Shelf** – when the app is highlighted in the top row of the Home screen, the background shows live graphs from a dashboard view (chosen in Settings; by default the first view with graphs). Drawn by a Top Shelf extension that shares the sign-in through an App Group.
- **Cameras** – live HLS stream (needs the `stream` integration), falling back to 1-second snapshots.
- **Server discovery** via Bonjour, so you rarely need to type the address.
- Hidden, disabled, config and diagnostic entities are left out.
- The token is kept in the Keychain.

## Layout

```
HomeAssistantKit/   Swift package: models, REST + WebSocket clients, presentation logic, tests
App/Sources/        tvOS SwiftUI app
App/Resources/      Asset catalog
project.yml         XcodeGen spec for the app project
```

## Building

Requires Xcode 15 or later with the tvOS SDK.

```sh
brew install xcodegen
xcodegen generate
open HomeAssistantTV.xcodeproj
```

Select your team under *Signing & Capabilities*, choose an Apple TV simulator or device, and run.

Run the library tests (no Xcode needed):

```sh
swift test --package-path HomeAssistantKit
```

Screenshot every tab against a real server (UI test; it only moves focus, never operates devices):

```sh
TEST_RUNNER_HA_URL=http://homeassistant.local:8123 TEST_RUNNER_HA_TOKEN="$(pbpaste)" \
TEST_RUNNER_SCREENSHOT_DIR=/tmp/ha-tour \
  xcodebuild test -project HomeAssistantTV.xcodeproj -scheme HomeAssistantTV \
  -destination 'platform=tvOS Simulator,name=Apple TV 4K (3rd generation)'
```

App icon and Top Shelf images are drawn by `scripts/generate-icons.swift`; run `swift scripts/generate-icons.swift` after changing it.

## Signing in

1. In Home Assistant, open your **Profile → Security → Long-lived access tokens** and create a token.
2. On the Apple TV, pick your server from the discovered list (or type its address, e.g. `homeassistant.local:8123`).
3. Select the token field. Your iPhone will show a keyboard notification, so you can paste the token there instead of typing it with the remote.

In the simulator, debug builds can skip typing: copy the token on your Mac, then launch with

```sh
SIMCTL_CHILD_HA_URL=http://homeassistant.local:8123 SIMCTL_CHILD_HA_TOKEN="$(pbpaste)" \
  xcrun simctl launch booted uk.co.peterbraden.HomeAssistantTV
```

Add `SIMCTL_CHILD_HA_AUTOCONNECT=1` to sign in straight away instead of choosing Connect.

Grouping by room reads the area, device and entity registries, which needs an **admin** user. With a non-admin token the app still works, but without the Rooms tab.

## Notes

- App Transport Security allows plain HTTP, because most Home Assistant installs are served over HTTP on the LAN.
- Remote Menu/Back closes detail sheets and the camera view.
