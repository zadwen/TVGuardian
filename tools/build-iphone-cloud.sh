#!/bin/bash
# Run on a GitHub-hosted Mac. Apple credentials are deliberately unnecessary
# here: signing and provisioning happen later in the user's Windows installer.
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"

if [[ "$(uname -s)" != "Darwin" ]]; then
  printf '%s\n' 'This script runs on the cloud macOS runner, not directly on Windows.' >&2
  exit 1
fi
for tool in xcodebuild xcrun node python3 ditto unzip shasum; do
  command -v "$tool" >/dev/null || { printf 'Required build tool missing: %s\n' "$tool" >&2; exit 1; }
done

BUNDLE_ID="${TVGUARDIAN_BUNDLE_ID:-com.zadwen.TVGuardian}"
if [[ ! "$BUNDLE_ID" =~ ^[A-Za-z0-9][A-Za-z0-9-]*(\.[A-Za-z0-9][A-Za-z0-9-]*){2,}$ ]]; then
  printf '%s\n' 'Use a reverse-DNS bundle identifier containing letters, digits, dots and hyphens.' >&2
  exit 1
fi

mkdir -p "$PROJECT_ROOT/build/cloud-artifacts"
ARTIFACTS="$PROJECT_ROOT/build/cloud-artifacts"
RUN_DIRECTORY="$(mktemp -d "$PROJECT_ROOT/build/cloud-run.XXXXXXXX")"
RESULT_BUNDLE_PATH="$RUN_DIRECTORY/TVGuardian-tests.xcresult"
collect_test_results() {
  local original_status=$?
  trap - EXIT
  if [[ -d "$RESULT_BUNDLE_PATH" ]]; then
    ditto "$RESULT_BUNDLE_PATH" "$ARTIFACTS/TVGuardian-tests.xcresult" || true
    xcrun xcresulttool export attachments --path "$RESULT_BUNDLE_PATH" --output-path "$ARTIFACTS/ui-screenshots" >/dev/null 2>&1 || true
  fi
  exit "$original_status"
}
trap collect_test_results EXIT
xcodebuild -version | tee "$ARTIFACTS/xcode-version.log"
node --test bridge/test/*.test.mjs companion/test/*.test.mjs tools/test/*.test.mjs 2>&1 | tee "$ARTIFACTS/contracts.log"

xcrun simctl list devices available -j > "$RUN_DIRECTORY/simulators.json"
SIMULATOR_ID="$(python3 - "$RUN_DIRECTORY/simulators.json" <<'PY'
import json
import re
import sys
with open(sys.argv[1], encoding='utf-8') as source:
    inventory = json.load(source)
phones = [device for runtime, devices in inventory['devices'].items()
          if 'iOS-' in runtime for device in devices
          if device.get('isAvailable', False) and device['name'].startswith('iPhone')]
if not phones:
    raise SystemExit('No available iPhone simulator; the build is not verified.')
identifier = phones[0]['udid']
if not re.fullmatch(r'[A-Fa-f0-9-]{36}', identifier):
    raise SystemExit('Simulator identifier was malformed.')
print(identifier)
PY
)"

# Simulator tests use the project's own app/test identifiers. The device archive
# then overrides only the application identifier; no signing team is supplied.
xcodebuild test \
  -project ios/TVGuardian.xcodeproj \
  -scheme TVGuardian \
  -destination "platform=iOS Simulator,arch=arm64,id=$SIMULATOR_ID" \
  -parallel-testing-enabled NO \
  -resultBundlePath "$RESULT_BUNDLE_PATH" \
  CODE_SIGNING_ALLOWED=NO \
  2>&1 | tee "$ARTIFACTS/ios-tests.log"

xcodebuild archive \
  -project ios/TVGuardian.xcodeproj \
  -scheme TVGuardian \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath "$RUN_DIRECTORY/TVGuardian.xcarchive" \
  -derivedDataPath "$RUN_DIRECTORY/DerivedData" \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= DEVELOPMENT_TEAM= \
  "PRODUCT_BUNDLE_IDENTIFIER=$BUNDLE_ID" \
  2>&1 | tee "$ARTIFACTS/ios-archive.log"

APP="$RUN_DIRECTORY/TVGuardian.xcarchive/Products/Applications/TVGuardian.app"
if [[ ! -f "$APP/TVGuardian" || ! -f "$APP/Info.plist" ]]; then
  printf '%s\n' 'Xcode did not produce the expected device app; no IPA will be published.' >&2
  exit 1
fi
python3 - "$APP/Info.plist" "$BUNDLE_ID" <<'PY'
import plistlib
import sys
with open(sys.argv[1], 'rb') as source:
    info = plistlib.load(source)
if info.get('CFBundleIdentifier') != sys.argv[2] or 'iPhoneOS' not in info.get('CFBundleSupportedPlatforms', []):
    raise SystemExit('The output is not the requested iPhone device build.')
PY

mkdir -p "$RUN_DIRECTORY/Package/Payload"
ditto "$APP" "$RUN_DIRECTORY/Package/Payload/TVGuardian.app"
IPA="$ARTIFACTS/TVGuardian-unsigned.ipa"
ditto -c -k --keepParent "$RUN_DIRECTORY/Package/Payload" "$IPA"
unzip -t "$IPA" | tee "$ARTIFACTS/ipa-validation.log"
(
  cd "$ARTIFACTS"
  shasum -a 256 TVGuardian-unsigned.ipa > TVGuardian-unsigned.ipa.sha256
)
cat > "$ARTIFACTS/INSTALL-NEXT.txt" <<'TEXT'
TV Guardian device build

This IPA is compiled but UNSIGNED. It cannot be installed by tapping it.
Simulator tests passed in this workflow; Samsung TV hardware has not been tested.

On Windows, install AltServer and AltStore Classic using the official guide:
https://faq.altstore.io/altstore-classic/how-to-install-altstore-windows
Then import TVGuardian-unsigned.ipa into AltStore on your iPhone while AltServer
is running. The installer performs Apple signing/provisioning for your account.
Enter Apple credentials only into the installer, not GitHub workflow secrets.
With a free account, expect seven-day renewal and Apple's app/identifier limits.

Keep your bundle identifier and signing account consistent for future updates.
See docs/WINDOWS.md for the complete workflow and limitations.
TEXT
printf '%s\n' 'Created unsigned device IPA after successful tests and archive. Windows signing is still required.'
