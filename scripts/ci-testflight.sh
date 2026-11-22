#!/usr/bin/env bash
# 明暗カメラ: GitHub Actions から App Store Connect(TestFlight) へ配信する。
# 必要な Secrets: APP_STORE_CONNECT_KEY_ID / APP_STORE_CONNECT_ISSUER_ID /
#                 APP_STORE_CONNECT_PRIVATE_KEY(p8の中身) / APPLE_TEAM_ID
set -euo pipefail

APP_NAME="LiveValueCamera"
SCHEME="LiveValueCamera"
BUILD_NUMBER="${BUILD_NUMBER:-1}"

: "${KEY_ID:?APP_STORE_CONNECT_KEY_ID is missing}"
: "${ISSUER_ID:?APP_STORE_CONNECT_ISSUER_ID is missing}"
: "${TEAM_ID:?APPLE_TEAM_ID is missing}"
: "${PRIVATE_KEY:?APP_STORE_CONNECT_PRIVATE_KEY is missing}"

echo "== Toolchain"
xcodebuild -version
ls -d /Applications/Xcode*.app || true

echo "== 計算ロジックの自己点検"
python3 scripts/verify-logic.py

echo "== XcodeGen"
if ! command -v xcodegen >/dev/null 2>&1; then
  brew install xcodegen
fi
xcodegen generate
xcodebuild -list -project "$APP_NAME.xcodeproj"

echo "== Info.plist の申告（暗号化・カメラ・広告）"
grep -A1 '<key>ITSAppUsesNonExemptEncryption</key>' Resources/Info.plist | grep -q '<false/>'
grep -q '<key>NSCameraUsageDescription</key>' Resources/Info.plist
grep -q '<key>NSPhotoLibraryAddUsageDescription</key>' Resources/Info.plist
grep -A1 '<key>GADApplicationIdentifier</key>' Resources/Info.plist | grep -q 'ca-app-pub-'

echo "== Install App Store Connect API key"
KEY_DIR="$HOME/.appstoreconnect/private_keys"
mkdir -p "$KEY_DIR"
printf '%s\n' "$PRIVATE_KEY" > "$KEY_DIR/AuthKey_${KEY_ID}.p8"
chmod 600 "$KEY_DIR/AuthKey_${KEY_ID}.p8"
KEY_PATH="$RUNNER_TEMP/AuthKey_${KEY_ID}.p8"
printf '%s\n' "$PRIVATE_KEY" > "$KEY_PATH"
chmod 600 "$KEY_PATH"

echo "== Archive (build $BUILD_NUMBER)"
# このチームには端末が登録されていないため、開発用プロファイルは発行されない。
# そのためアーカイブは署名なしで作り、書き出し（export）で配布用に署名する。
# ただし SPM のバイナリ（GoogleMobileAds など）は、署名なしのままだと
# 書き出しでも再署名されず ITMS-90035 で弾かれる。仮署名（ad-hoc）を付けておくと
# 書き出し時に配布証明書で署名し直される。
ARCHIVE="$RUNNER_TEMP/${APP_NAME}.xcarchive"
rm -rf "$ARCHIVE"
xcodebuild archive \
  -project "$APP_NAME.xcodeproj" \
  -scheme "$SCHEME" \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath "$ARCHIVE" \
  -allowProvisioningUpdates \
  -authenticationKeyPath "$KEY_PATH" \
  -authenticationKeyID "$KEY_ID" \
  -authenticationKeyIssuerID "$ISSUER_ID" \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=""

echo "== 埋め込みフレームワークに仮署名"
APP_PATH="$ARCHIVE/Products/Applications/${APP_NAME}.app"
if [ -d "$APP_PATH/Frameworks" ]; then
  for item in "$APP_PATH"/Frameworks/*; do
    [ -e "$item" ] || continue
    /usr/bin/codesign --force --sign - --timestamp=none "$item" >/dev/null 2>&1 || true
    if /usr/bin/codesign --verify --strict "$item" >/dev/null 2>&1; then
      echo "ad-hoc signed: $(basename "$item")"
    else
      echo "WARNING: 仮署名に失敗: $(basename "$item")"
    fi
  done
fi

echo "== ExportOptions"
EXPORT_OPTIONS="$RUNNER_TEMP/ExportOptions.plist"
rm -f "$EXPORT_OPTIONS"
plutil -create xml1 "$EXPORT_OPTIONS"
plutil -insert method -string app-store-connect "$EXPORT_OPTIONS"
plutil -insert teamID -string "$TEAM_ID" "$EXPORT_OPTIONS"
plutil -insert signingStyle -string automatic "$EXPORT_OPTIONS"
plutil -insert destination -string export "$EXPORT_OPTIONS"
plutil -insert manageAppVersionAndBuildNumber -bool false "$EXPORT_OPTIONS"
plutil -insert uploadSymbols -bool true "$EXPORT_OPTIONS"
plutil -insert stripSwiftSymbols -bool true "$EXPORT_OPTIONS"
plutil -lint "$EXPORT_OPTIONS"

echo "== Export IPA (cloud signing)"
EXPORT_DIR="$RUNNER_TEMP/export"
rm -rf "$EXPORT_DIR"
mkdir -p "$EXPORT_DIR"
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportOptionsPlist "$EXPORT_OPTIONS" \
  -exportPath "$EXPORT_DIR" \
  -allowProvisioningUpdates \
  -authenticationKeyPath "$KEY_PATH" \
  -authenticationKeyID "$KEY_ID" \
  -authenticationKeyIssuerID "$ISSUER_ID"

IPA=$(ls -1 "$EXPORT_DIR"/*.ipa | head -n 1)
test -n "$IPA"
echo "IPA: $IPA"
unzip -p "$IPA" "Payload/*.app/Info.plist" > "$RUNNER_TEMP/ipa-info.plist" || true
plutil -extract CFBundleIdentifier raw -o - "$RUNNER_TEMP/ipa-info.plist" || true
plutil -extract CFBundleShortVersionString raw -o - "$RUNNER_TEMP/ipa-info.plist" || true
plutil -extract CFBundleVersion raw -o - "$RUNNER_TEMP/ipa-info.plist" || true

echo "== 書き出した IPA の署名を確認"
CHECK_DIR="$RUNNER_TEMP/ipa-check"
rm -rf "$CHECK_DIR"
mkdir -p "$CHECK_DIR"
unzip -q "$IPA" -d "$CHECK_DIR" || true
for item in "$CHECK_DIR/Payload/${APP_NAME}.app/Frameworks"/*; do
  [ -e "$item" ] || continue
  echo "--- $(basename "$item")"
  /usr/bin/codesign -dv "$item" 2>&1 | grep -E "Authority|Signature|TeamIdentifier" || true
done

echo "== Upload to TestFlight"
xcrun altool --upload-app -f "$IPA" -t ios \
  --apiKey "$KEY_ID" --apiIssuer "$ISSUER_ID" --output-format json

echo "== Done: build $BUILD_NUMBER uploaded"
