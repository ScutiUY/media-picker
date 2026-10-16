#!/bin/zsh
# MediaPicker.app(Apple Silicon + Intel)을 빌드해 build/ 에 만든다.
# 인자로 --install 을 주면 /Applications 에 복사하고 실행한다.
set -euo pipefail
cd "$(dirname "$0")"

ARCHS=(arm64 x86_64)
SWIFT_FLAGS=(-c release)
for arch in $ARCHS; do SWIFT_FLAGS+=(--arch $arch); done
swift build $SWIFT_FLAGS
BIN=$(swift build $SWIFT_FLAGS --show-bin-path)

APP=build/MediaPicker.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/MediaPicker" "$APP/Contents/MacOS/"
cp Resources/Info.plist "$APP/Contents/"
cp -R Resources/*.lproj "$APP/Contents/Resources/"
cp Resources/AppIcon.icns "$APP/Contents/Resources/"
cp -R Extension "$APP/Contents/Resources/"

# 사파리 웹 확장(.appex): 같은 확장 파일을 앱 안의 PlugIns에 넣는다.
APPEX="$APP/Contents/PlugIns/MediaPickerSafari.appex"
mkdir -p "$APPEX/Contents/MacOS" "$APPEX/Contents/Resources"
cp Safari/Info.plist "$APPEX/Contents/"
cp Resources/AppIcon.icns "$APPEX/Contents/Resources/"
cp -R Extension/ "$APPEX/Contents/Resources/"
SLICES=()
for arch in $ARCHS; do
    swiftc -O -parse-as-library -application-extension -module-name MediaPickerSafari \
        -target "$arch-apple-macos14.0" \
        -Xlinker -e -Xlinker _NSExtensionMain \
        Safari/SafariWebExtensionHandler.swift -o "build/MediaPickerSafari-$arch"
    SLICES+="build/MediaPickerSafari-$arch"
done
lipo -create $SLICES -output "$APPEX/Contents/MacOS/MediaPickerSafari"
rm -f $SLICES

# 서명이 바뀌면 손쉬운 사용 권한이 풀린다. 언제나 같은 인증서로 서명한다.
# 1순위: 자체 서명 'MediaPicker Release Signing'(배포용, 만료·폐기 걱정 없음)
# 2순위: Apple Development, 없으면 ad-hoc
SIGNING_NAME="MediaPicker Release Signing"
if security find-certificate -c "$SIGNING_NAME" >/dev/null 2>&1; then
    IDENTITY=$SIGNING_NAME
else
    IDENTITY=$(security find-identity -v -p codesigning | awk -F'"' '/Apple Development|Developer ID Application/ {print $2; exit}')
fi
codesign --force --sign "${IDENTITY:--}" --entitlements Safari/Safari.entitlements "$APPEX"
codesign --force --sign "${IDENTITY:--}" "$APP"
echo "built $APP (${IDENTITY:-ad-hoc})"

if [[ "${1:-}" == "--install" ]]; then
    pkill -x MediaPicker || true
    rm -rf /Applications/MediaPicker.app
    cp -R "$APP" /Applications/
    open /Applications/MediaPicker.app
    echo "installed /Applications/MediaPicker.app"
fi
