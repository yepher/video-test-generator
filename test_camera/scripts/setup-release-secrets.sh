#!/bin/sh
# One-time setup for .github/workflows/release.yml. Run it on your Mac from anywhere in the repo:
#
#   test_camera/scripts/setup-release-secrets.sh
#
# 1. Stores the Sparkle private key from your Keychain (the same key livekit-observer uses; its public
#    half is already in TestCamera/Info.plist) as the SPARKLE_PRIVATE_KEY secret.
# 2. Stores your Developer ID Application certificate, exported from Keychain Access as a .p12.
# 3. Stores the two Developer ID provisioning profiles the camera system extension needs, and installs
#    them locally so Release builds and Xcode archives work on this Mac too.
# 4. Stores your Apple ID and an app-specific password, for notarization.
#
# Secrets go to GitHub with `gh secret set` over stdin; nothing is printed or left on disk.
set -eu
cd "$(dirname "$0")/.."
SPARKLE_VERSION=2.10.1
REPO=yepher/video-test-generator
command -v gh > /dev/null || { echo "Install the GitHub CLI: brew install gh"; exit 1; }

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

echo "== Sparkle update key"
curl -sSL "https://github.com/sparkle-project/Sparkle/releases/download/$SPARKLE_VERSION/Sparkle-$SPARKLE_VERSION.tar.xz" | tar xJ -C "$work"
"$work/bin/generate_keys" > /dev/null  # creates the key, or does nothing if it already exists
public_key="$("$work/bin/generate_keys" -p)"
/usr/libexec/PlistBuddy -c "Set :SUPublicEDKey $public_key" TestCamera/Info.plist
echo "Public key in TestCamera/Info.plist: $public_key"
(umask 077; "$work/bin/generate_keys" -x "$work/sparkle.key" > /dev/null)
gh secret set SPARKLE_PRIVATE_KEY -R "$REPO" < "$work/sparkle.key"

echo
echo "== Developer ID Application certificate"
echo "In Keychain Access, under My Certificates, right-click \"Developer ID Application: Chris Wilson (WDCGJTU726)\","
echo "choose Export, and save it as a .p12 with a password."
printf "Path to the .p12: "; read -r p12
printf "Its password: "; stty -echo; read -r p12_password; stty echo; echo
base64 -i "$p12" | gh secret set DEVELOPER_ID_P12_BASE64 -R "$REPO"
printf '%s' "$p12_password" | gh secret set DEVELOPER_ID_P12_PASSWORD -R "$REPO"
echo "Stored. You can delete $p12 now."

echo
echo "== Developer ID provisioning profiles"
echo "At https://developer.apple.com/account/resources/profiles create two profiles of type"
echo "\"Developer ID\" (macOS), using the Developer ID Application certificate:"
echo "  - App ID com.yepher.vidtiming.testcamera            (System Extension + App Groups), named \"VideoTestCamera\""
echo "  - App ID com.yepher.vidtiming.testcamera.extension  (App Groups),                    named \"VideoTestCameraExtension\""
echo "Both App IDs need the app group group.com.yepher.vidtiming.testcamera. Download both profiles."
installed="$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles"
mkdir -p "$installed"
for kind in APP EXTENSION; do
  printf "Path to the %s profile: " "$(echo "$kind" | tr '[:upper:]' '[:lower:]')"; read -r profile
  name="$(security cms -D -i "$profile" | plutil -extract Name raw -o - -)"
  echo "  $name"
  base64 -i "$profile" | gh secret set "TESTCAMERA_${kind}_PROFILE_BASE64" -R "$REPO"
  cp "$profile" "$installed/$(security cms -D -i "$profile" | plutil -extract UUID raw -o - -).provisionprofile"
done

echo
echo "== Notarization"
echo "Use an app-specific password from https://account.apple.com (Sign-In and Security > App-Specific Passwords)."
printf "Apple ID email: "; read -r apple_id
printf "App-specific password: "; stty -echo; read -r app_password; stty echo; echo
printf '%s' "$apple_id" | gh secret set NOTARY_APPLE_ID -R "$REPO"
printf '%s' "$app_password" | gh secret set NOTARY_PASSWORD -R "$REPO"

echo
echo "Done. Release with: git tag v1.0.0 && git push origin v1.0.0"
