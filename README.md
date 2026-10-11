# Home Assistant for Apple TV

A native tvOS app (SwiftUI, tvOS 17+) for controlling Home Assistant from the couch.

## Features

- **Rooms tab** – every controllable entity grouped by Home Assistant area.
- **Dashboards tab** – your Lovelace dashboards drawn natively (tvOS has no web view), including history graphs, statistics graphs, statistic and sensor cards, entity lists, cameras and markdown. Card types not yet supported show a placeholder; auto-generated and strategy dashboards (e.g. Map) are skipped.
- **Energy** – when Home Assistant's Energy dashboard is set up, an Energy choice in the Dashboards tab shows stacked daily (or monthly) consumption for the grid, solar and each tracked device over a week, month or year, with totals.
- **Devices tab** – every entity by category (Lights, Climate, Media, Security, Scenes, Automations, Controls, Sensors), picked from a row of buttons. One tab for all categories keeps the tab bar within tvOS's 7-tab limit.
- **Live updates** over the WebSocket API, with automatic reconnect.
- **One-click actions** – clicking a tile toggles lights/switches/fans or runs scenes, scripts and buttons. Long-press any tile for details.
- **Detail controls**
  - Lights: on/off, brightness steps and presets, white temperature, colors
  - Climate: target temperature (single or range), HVAC mode, presets, fan mode
  - Media players: artwork, play/pause/skip, volume, mute, power, source
  - Covers/valves, locks, alarm panels (with code entry), vacuums, fans
- **Top Shelf** – when the app is highlighted in the top row of the Home screen, the background shows live graphs from a dashboard view (chosen in Settings; by default the first view with graphs). Drawn by a Top Shelf extension that shares the sign-in through an App Group.
- **Media tab** – browse every Home Assistant media source (Radio Browser, local media, cameras, Jellyfin, DLNA, Synology Photos, TTS…) and the libraries of speakers and TVs. Select plays on the Apple TV itself through the system player (Siri Remote controls, Now Playing, Picture in Picture for video; audio keeps playing in the background). Long-press to send an item to a Home Assistant media player; playing from a speaker's own library asks first.
- **Map tab** – people (with their pictures) and device trackers not assigned to a person, on Apple Maps with your zones drawn as circles; a side list shows who is where and since when. Shown only when something reports a location.
- **Doorbell and notifications** – when a doorbell event entity fires while the app is open, a card offers to open your locks, show a camera, or dismiss (focus starts on Dismiss); over the full-screen player the same actions appear as player buttons. New Home Assistant notifications pop up briefly and are listed in Settings, where selecting one dismisses it.
- **Assist** – search devices, or send the same words to Home Assistant Assist (hold the Siri Remote mic to dictate). Text only goes to Assist when you press "Ask Assist", so searching for a device never operates it. The agent defaults to the preferred pipeline and can be changed in Settings. **Announce…** speaks the same text on a chosen speaker through text-to-speech (`tts.speak`, preferring a local engine such as Piper).
- **Entity details** – besides controls: a 24-hour graph for numeric sensors, recent logbook activity (with what caused each change) for everything else, and a daily forecast for weather entities.
- **Automations, selects, numbers and updates** – enable, disable or run automations; pick options and step numbers (including `input_*` helpers); pending updates are listed in Settings and install after confirmation.
- **Links** – `homeassistanttv://entity/<entity_id>` opens an entity's details; `dashboards`, `media`, `map`, `assist`, `devices[/<category>]` and `settings` open those tabs.
- **Keep dashboards on screen** – optional setting that holds off the screen saver while a dashboard is showing.
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

To test without pressing select, `SIMCTL_CHILD_OPEN_URL=<homeassistanttv:// link>` follows a link at launch; `SIMCTL_CHILD_MEDIA_PATH=<media-source ID>` (or `root`) opens the Media tab at that folder, and `SIMCTL_CHILD_MEDIA_PLAY=<media-source ID>` (with optional `SIMCTL_CHILD_MEDIA_TITLE`) plays it on the Apple TV. `SIMCTL_CHILD_SIMULATE_DOORBELL=<event entity>` and `SIMCTL_CHILD_SIMULATE_NOTIFICATION=<text>` show the alerts.

Grouping by room reads the area, device and entity registries, which needs an **admin** user. With a non-admin token the app still works, but without the Rooms tab.

## Notes

- App Transport Security allows plain HTTP, because most Home Assistant installs are served over HTTP on the LAN.
- Remote Menu/Back closes detail sheets and the camera view.
