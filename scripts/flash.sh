#!/usr/bin/env bash
# Builds KeePassIOS and installs it on a connected iPhone or iPad, without
# opening Xcode. Uses the command-line tools that come with Xcode
# (xcodebuild, xcrun devicectl).
#
#   scripts/flash.sh                 build Debug, install, launch
#   scripts/flash.sh --release       build Release instead
#   scripts/flash.sh --device NAME   pick a device by name or identifier
#   scripts/flash.sh --no-launch     install only
#   scripts/flash.sh --list          list connected devices and exit
#
# First run: the device must be paired (connect it once by cable and tap
# "Trust"), Developer Mode must be on (Settings > Privacy & Security), and
# Xcode must be signed in to the Apple ID of the development team set in
# the project. Automatic signing creates the provisioning profile.
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

configuration="Debug"
device=""
launch=1
bundle_id="dev.guilhermenl.keepassios"
derived_data="${TMPDIR:-/tmp}/keepassios-flash"

while (($#)); do
  case "$1" in
    --release) configuration="Release" ;;
    --device) device="$2"; shift ;;
    --no-launch) launch=0 ;;
    --list)
      xcrun devicectl list devices
      exit 0
      ;;
    -h | --help)
      sed -n '2,17p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      echo "flash: unknown argument: $1" >&2
      exit 2
      ;;
  esac
  shift
done

if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "flash: xcodebuild not found. Install Xcode (it provides the command-line build tools)." >&2
  exit 1
fi

# Pick the device: the one named, or the only connected one.
devices_json="$(mktemp)"
trap 'rm -f "$devices_json"' EXIT
xcrun devicectl list devices --json-output "$devices_json" >/dev/null
read -r device_id device_udid < <(
  python3 - "$devices_json" "$device" <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))
wanted = sys.argv[2].lower()
devices = [
    d for d in data.get("result", {}).get("devices", [])
    if d.get("hardwareProperties", {}).get("platform") == "iOS"
    and d.get("connectionProperties", {}).get("pairingState") == "paired"
]
if wanted:
    devices = [
        d for d in devices
        if wanted in (d.get("deviceProperties", {}).get("name", "").lower(),
                      d.get("identifier", "").lower(),
                      d.get("hardwareProperties", {}).get("udid", "").lower())
    ]
if len(devices) != 1:
    names = ", ".join(d.get("deviceProperties", {}).get("name", "?") for d in devices) or "none"
    sys.stderr.write(f"flash: need exactly one paired iOS device, found: {names}. Use --device NAME.\n")
    sys.exit(1)
# devicectl addresses devices by identifier, xcodebuild by UDID.
print(devices[0]["identifier"], devices[0]["hardwareProperties"]["udid"])
PY
)
if [[ -z "${device_id:-}" ]]; then
  exit 1
fi
echo "Device: $device_id"

echo "Building ${configuration}..."
build_log="$(mktemp)"
trap 'rm -f "$devices_json" "$build_log"' EXIT
if ! xcodebuild build \
  -project keepassios.xcodeproj \
  -scheme keepassios \
  -configuration "$configuration" \
  -destination "id=$device_udid" \
  -derivedDataPath "$derived_data" \
  -allowProvisioningUpdates \
  -quiet 2>&1 | tee "$build_log"; then
  # Signing failures are the usual first-run problem; say what to do.
  if grep -q "PLA Update available" "$build_log"; then
    echo "flash: Apple has a new Program License Agreement. The account holder must accept it at" >&2
    echo "       https://developer.apple.com/account before Xcode can create provisioning profiles." >&2
  elif grep -q "doesn't include the App Groups capability\|No Account for Team\|No profiles for" "$build_log"; then
    echo "flash: Xcode couldn't create a provisioning profile. Open Xcode > Settings > Accounts once and" >&2
    echo "       make sure the Apple ID for the project's team is signed in, then run this again." >&2
  fi
  exit 1
fi

app="$derived_data/Build/Products/$configuration-iphoneos/keepassios.app"
if [[ ! -d "$app" ]]; then
  echo "flash: build finished but $app is missing" >&2
  exit 1
fi

# AutoFill only works when the extension is inside the app.
extension="$app/PlugIns/KeePassIOSAutoFill.appex"
if [ ! -d "$extension" ]; then
  echo "flash: warning: $extension is missing; AutoFill won't be offered" >&2
elif ! /usr/libexec/PlistBuddy -c "Print :NSExtension:NSExtensionPointIdentifier" "$extension/Info.plist" >/dev/null 2>&1; then
  echo "flash: warning: the AutoFill extension's Info.plist has no NSExtension entry" >&2
fi

echo "Installing..."
xcrun devicectl device install app --device "$device_id" "$app"

if ((launch)); then
  echo "Launching..."
  xcrun devicectl device process launch --device "$device_id" --terminate-existing "$bundle_id"
fi
echo "Done."
echo "AutoFill: tap Turn On AutoFill in the app (library or Settings) once per install."
