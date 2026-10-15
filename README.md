# MediaPicker

**Hold F8 to choose what plays.**

You paused a YouTube tab an hour ago. Now you press ▶︎ to resume Spotify — and the YouTube tab starts playing instead.
MediaPicker takes over the media keys so ▶︎ goes where you meant, and lets you pick any player with one hand, without leaving the function row.

[![Release](https://img.shields.io/github/v/release/ScutiUY/media-picker)](https://github.com/ScutiUY/media-picker/releases/latest)
![macOS 14+](https://img.shields.io/badge/macOS-14%2B-blue)
[![License: MIT](https://img.shields.io/badge/license-MIT-green)](LICENSE)

[한국어](README.ko.md)

## How it works

**F8 tap** pauses whatever is actually playing. When nothing is playing, it resumes the last thing *you* played — not whichever app macOS happens to remember.

**F8 hold** opens a small picker listing everything that can play right now:

```
 Choose what to play
 ▶︎  The Less I Know the Better     Spotify · Tame Impala       ▮▮▮▮▮▮▯▯▯▯ 60%
 ❚❚  Lofi beats to study to         Chrome · youtube.com        ▮▮▮▮▮▮▮▮▯▯ 80%
 ❚❚  Episode 12                     Safari · netflix.com        ▮▮▮▮▮▮▮▮▮▮ 100%
 F8 tap: next · hold: play/pause · F7·F9 skip · F10–F12 volume
```

Keep your hand where it is: tap F8 to move down the list, hold F8 to play the highlighted item. Everything else pauses.

| Key | Picker closed | Picker open |
|---|---|---|
| F8 tap | Pause what's playing / resume the last one | Move to the next item |
| F8 hold | Open the picker | Play/pause the highlighted item and close |
| F7 / F9 | Previous / next for what's playing | Previous / next for the highlighted item |
| F10 / F11 / F12 | System mute / volume, as usual | Mute / volume for the highlighted item only |

## What it controls

| Source | How | Per-item volume |
|---|---|---|
| Spotify, Music, TV, VLC | AppleScript | ✓ |
| Chrome, Edge, Brave, Arc tabs | Browser extension | ✓ |
| Safari tabs | Safari extension, or "Allow JavaScript from Apple Events" | ✓ |
| Anything else making sound (Firefox, IINA, …) | Detected through Core Audio, controlled with the system media key | — |

YouTube and Netflix get site-specific skip; on other sites F7/F9 jump 10 seconds. Call apps (Zoom, FaceTime, Discord, Teams, Slack…) are never touched.

## Install

1. Download **MediaPicker-x.y.z.dmg** from [Releases](https://github.com/ScutiUY/media-picker/releases/latest) and drag MediaPicker to Applications.
2. **Open it once.** The app is not notarized by Apple (this is a free side project without a paid developer account), so macOS blocks the first launch.
   Go to **System Settings › Privacy & Security** and click **Open Anyway**.
   Or in Terminal: `xattr -dr com.apple.quarantine /Applications/MediaPicker.app`
3. **Allow Accessibility** when asked. MediaPicker needs it to catch the media keys before macOS sends them to the wrong app.
   Every release is signed with the same certificate, so updates keep the permission.
4. **Browser tabs:** menu bar icon › **Install Browser Extension…**
   - Chrome, Edge, Brave, Arc: the app copies the extension to a folder; load it from `chrome://extensions` › Developer mode › **Load unpacked**.
   - Safari: the extension is inside the app. Without notarization Safari only lists it after **Settings › Developer › Allow unsigned extensions**, which resets when Safari quits. Until then, Safari tabs work through **Develop › Allow JavaScript from Apple Events**.

Requires macOS 14 Sonoma or later. Apple Silicon and Intel. English, Korean, Japanese, Simplified and Traditional Chinese.

## Troubleshooting

- **F8 does nothing / the menu bar icon shows a warning:** Accessibility permission is missing. Menu bar icon › Accessibility Permission…, turn MediaPicker off and on.
- **A browser tab isn't listed:** check that the menu shows "Extension: Chrome". After updating the app, press ↻ on the extension in `chrome://extensions`.
- **Volume won't go above a certain level:** per-item volume is the app's own volume, so the system volume is the ceiling.
- **Logs:** menu bar icon › Show Log (`~/Library/Logs/MediaPicker.log`).

## Privacy

Everything stays on your Mac. The extension talks only to the app on `127.0.0.1:17872`, and the app accepts connections only from browser extensions, so web pages can't reach it. No analytics, no network requests.

## Build from source

Requires Xcode 16 or later.

```sh
./build.sh --install   # build a universal app and install it to /Applications
./release.sh           # build dist/: DMG, zip, extension zip, SHA256SUMS
```

`build.sh` signs with a certificate named `MediaPicker Release Signing` when it exists in your keychain, otherwise with your Apple Development identity, otherwise ad-hoc.

```
Sources/MediaPicker/
  MediaKeyTap.swift      CGEventTap that intercepts the media and volume keys
  MediaController.swift  decides what to play or pause
  Providers.swift        Spotify, Music, TV, VLC, Safari/Chromium via AppleScript
  BridgeServer.swift     local WebSocket server for the browser extension
  AudioActivity.swift    finds apps that are making sound (Core Audio)
  Picker.swift           the picker panel (SwiftUI)
Extension/               WebExtension shared by Chrome and Safari
Safari/                  Safari web extension wrapper (.appex)
```

## Related projects

If MediaPicker isn't what you need, these solve the same problem in different ways:
[Beamhook](https://beamhook.app) (pin the media keys to an app or tab from the menu bar),
SmartPause and mac-media-keys.

## License

MIT. A personal project — issues and pull requests are welcome, support is best effort.
