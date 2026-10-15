# MediaPicker

**F8을 길게 눌러 재생할 것을 고릅니다.**

한 시간 전에 유튜브 탭을 멈춰 뒀습니다. 이제 Spotify를 다시 틀려고 ▶︎를 누르면, Spotify 대신 그 유튜브 탭이 재생됩니다.
MediaPicker는 미디어키를 대신 받아서 ▶︎가 의도한 곳으로 가게 하고, 손을 펑션 키 줄에서 떼지 않고 한 손으로 재생할 것을 고르게 해 줍니다.

[![Release](https://img.shields.io/github/v/release/ScutiUY/media-picker)](https://github.com/ScutiUY/media-picker/releases/latest)
![macOS 14+](https://img.shields.io/badge/macOS-14%2B-blue)
[![License: MIT](https://img.shields.io/badge/license-MIT-green)](LICENSE)

[English](README.md)

## 동작 방식

**F8 짧게**는 실제로 재생 중인 것을 멈춥니다. 아무것도 재생 중이 아니면 macOS가 기억하는 아무 앱이 아니라 *내가* 마지막으로 재생한 것을 다시 틉니다.

**F8 길게**는 지금 재생할 수 있는 것을 모두 보여 주는 작은 선택 창을 엽니다.

```
 재생할 미디어 선택
 ▶︎  The Less I Know the Better     Spotify · Tame Impala       ▮▮▮▮▮▮▯▯▯▯ 60%
 ❚❚  Lofi beats to study to         Chrome · youtube.com        ▮▮▮▮▮▮▮▮▯▯ 80%
 ❚❚  Episode 12                     Safari · netflix.com        ▮▮▮▮▮▮▮▮▮▮ 100%
 F8 짧게 이동 · 길게 재생/정지 · F7·F9 이전·다음 · F10·F11·F12 볼륨
```

손은 그대로 두고 F8을 짧게 눌러 아래로 이동하고, 길게 눌러 강조된 항목을 재생합니다. 나머지는 모두 멈춥니다.

| 키 | 선택 창 닫힘 | 선택 창 열림 |
|---|---|---|
| F8 짧게 | 재생 중인 것 정지 / 마지막 것 재개 | 다음 항목으로 이동 |
| F8 길게 | 선택 창 열기 | 강조된 항목 재생·정지 후 닫기 |
| F7 / F9 | 재생 중인 것의 이전 / 다음 | 강조된 항목의 이전 / 다음 |
| F10 / F11 / F12 | 평소처럼 시스템 음소거 / 볼륨 | 강조된 항목만 음소거 / 볼륨 |

## 조작할 수 있는 것

| 대상 | 방법 | 항목별 볼륨 |
|---|---|---|
| Spotify, 음악, TV, VLC | AppleScript | ✓ |
| 크롬·엣지·브레이브·아크 탭 | 브라우저 확장 | ✓ |
| 사파리 탭 | 사파리 확장, 또는 'Apple Events의 JavaScript 허용' | ✓ |
| 그 밖에 소리 내는 앱 (Firefox, IINA 등) | Core Audio로 감지, 시스템 미디어키로 조작 | — |

유튜브와 넷플릭스는 사이트에 맞게 이전·다음으로 넘기고, 그 밖의 사이트에서는 F7/F9가 10초씩 이동합니다. 통화 앱(Zoom, FaceTime, Discord, Teams, Slack 등)은 건드리지 않습니다.

## 설치

1. [Releases](https://github.com/ScutiUY/media-picker/releases/latest)에서 **MediaPicker-x.y.z.dmg**를 받아 응용 프로그램 폴더로 끌어 놓습니다.
2. **한 번 실행합니다.** 유료 개발자 계정 없이 만든 무료 개인 프로젝트라 Apple 공증을 받지 않았고, 그래서 macOS가 첫 실행을 막습니다.
   **시스템 설정 › 개인정보 보호 및 보안**에서 **그래도 열기**를 누르세요.
   또는 터미널에서: `xattr -dr com.apple.quarantine /Applications/MediaPicker.app`
3. **손쉬운 사용 권한을 허용합니다.** macOS가 미디어키를 엉뚱한 앱에 보내기 전에 받으려면 필요합니다.
   모든 릴리스를 같은 인증서로 서명하므로 업데이트해도 권한이 유지됩니다.
4. **브라우저 탭:** 메뉴바 아이콘 › **브라우저 확장 설치…**
   - 크롬·엣지·브레이브·아크: 앱이 확장을 폴더에 복사해 줍니다. `chrome://extensions` › 개발자 모드 › **압축해제된 확장 프로그램 로드**로 불러오세요.
   - 사파리: 확장이 앱 안에 들어 있습니다. 공증 없이는 **설정 › 개발자 › 서명되지 않은 확장 프로그램 허용**을 켜야 보이고, 사파리를 끄면 풀립니다. 그 전까지는 **개발자용 › Apple Events의 JavaScript 허용**으로 사파리 탭을 조작할 수 있습니다.

macOS 14 Sonoma 이상, Apple Silicon·Intel 지원. 영어·한국어·일본어·중국어(간체·번체) 지원.

## 문제 해결

- **F8이 안 먹거나 메뉴바 아이콘에 경고가 뜸:** 손쉬운 사용 권한이 없는 상태입니다. 메뉴바 아이콘 › 손쉬운 사용 권한 설정…에서 MediaPicker를 껐다 켜세요.
- **브라우저 탭이 목록에 안 뜸:** 메뉴에 "확장: Chrome"이 보이는지 확인하세요. 앱을 업데이트한 뒤에는 `chrome://extensions`에서 확장의 ↻를 눌러 주세요.
- **볼륨이 일정 이상 안 올라감:** 항목별 볼륨은 각 앱 안의 볼륨이라서 시스템 볼륨이 최대치입니다.
- **로그:** 메뉴바 아이콘 › 로그 보기 (`~/Library/Logs/MediaPicker.log`)

## 개인정보

모든 처리는 맥 안에서만 이뤄집니다. 확장은 `127.0.0.1:17872`의 앱하고만 통신하고, 앱은 브라우저 확장에서 온 연결만 받으므로 웹페이지는 접근할 수 없습니다. 분석·외부 네트워크 요청 없음.

## 소스에서 빌드

Xcode 16 이상이 필요합니다.

```sh
./build.sh --install   # 유니버설 앱을 빌드해 /Applications에 설치
./release.sh           # dist/에 DMG, zip, 확장 zip, SHA256SUMS 생성
```

`build.sh`는 키체인에 `MediaPicker Release Signing` 인증서가 있으면 그것으로, 없으면 Apple Development 인증서로, 그것도 없으면 ad-hoc으로 서명합니다.

```
Sources/MediaPicker/
  MediaKeyTap.swift      미디어키·볼륨키를 가로채는 CGEventTap
  MediaController.swift  무엇을 재생·정지할지 결정
  Providers.swift        Spotify, 음악, TV, VLC, 사파리·크로미움 (AppleScript)
  BridgeServer.swift     브라우저 확장과 붙는 로컬 WebSocket 서버
  AudioActivity.swift    소리를 내는 앱 감지 (Core Audio)
  Picker.swift           선택 창 (SwiftUI)
Extension/               크롬·사파리 공용 WebExtension
Safari/                  사파리 웹 확장 래퍼 (.appex)
```

## 비슷한 프로젝트

MediaPicker가 맞지 않으면 같은 문제를 다른 방식으로 푸는 앱들도 있습니다:
[Beamhook](https://beamhook.app)(메뉴바에서 미디어키를 앱·탭에 고정), SmartPause, mac-media-keys.

## 라이선스

MIT. 개인 프로젝트라 이슈·PR은 환영하지만 지원은 가능한 범위에서만 합니다.
