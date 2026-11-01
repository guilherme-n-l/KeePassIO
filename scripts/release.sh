#!/usr/bin/env bash
# Builds KeePassIO for the App Store and uploads it to App Store Connect,
# where it appears in TestFlight after processing. Uses Xcode's
# command-line tools and the Apple ID signed in to Xcode, or an App Store
# Connect API key when ASC_KEY_PATH, ASC_KEY_ID and ASC_ISSUER_ID are set
# (the TestFlight workflow does this).
#
#   scripts/release.sh                    archive, export and upload
#   scripts/release.sh --no-upload        archive and export an .ipa only
#   scripts/release.sh --version 1.0.1    use this version instead of the tag
#
# Neither number lives in the project. The version shown to users comes
# from the release tag on the commit being built (v1.0.1 -> 1.0.1): tag a
# commit to release it. The build number is the number of commits, so
# every upload gets a higher one. The project's MARKETING_VERSION is only
# a placeholder for local builds.
#
# Needs: Xcode signed in to the team's Apple ID (or the API key above,
# with the Admin role so Xcode can use cloud-managed signing), the latest
# Apple Developer Program License Agreement accepted, and an app record
# for the bundle ID in App Store Connect.
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

upload=1
version=""
while (($#)); do
  case "$1" in
    --no-upload) upload=0 ;;
    --version)
      version="${2:?--version needs a value, e.g. 1.0.1}"
      shift
      ;;
    -h | --help)
      sed -n '2,21p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      echo "release: unknown argument: $1" >&2
      exit 2
      ;;
  esac
  shift
done

if [ -n "$(git status --porcelain)" ]; then
  echo "release: the working tree has uncommitted changes; commit them first so the build matches a commit" >&2
  exit 1
fi

# With an API key, xcodebuild signs and uploads as the key instead of the
# Apple ID signed in to Xcode.
auth=()
if [ -n "${ASC_KEY_PATH:-}" ]; then
  auth=(
    -authenticationKeyPath "$ASC_KEY_PATH"
    -authenticationKeyID "${ASC_KEY_ID:?ASC_KEY_ID is required with ASC_KEY_PATH}"
    -authenticationKeyIssuerID "${ASC_ISSUER_ID:?ASC_ISSUER_ID is required with ASC_KEY_PATH}"
  )
fi

if [ -z "$version" ]; then
  tag="$(git tag --points-at HEAD --list 'v*' --sort=-version:refname | head -n 1)"
  if [ -z "$tag" ]; then
    echo "release: no release tag on $(git rev-parse --short HEAD); tag it first (git tag v1.0.1) or pass --version" >&2
    exit 1
  fi
  version="${tag#v}"
fi
if ! [[ "$version" =~ ^[0-9]+(\.[0-9]+){1,2}$ ]]; then
  echo "release: '$version' isn't a version App Store Connect accepts (like 1.0 or 1.0.1)" >&2
  exit 1
fi

build_number="$(git rev-list --count HEAD)"
team_id="YXD4GPD63H"
out="build/release-$build_number"
archive="$out/KeePassIO.xcarchive"
rm -rf "$out"
mkdir -p "$out"

echo "Archiving version $version build $build_number ($(git rev-parse --short HEAD))..."
xcodebuild archive \
  -project keepassios.xcodeproj \
  -scheme keepassios \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath "$archive" \
  -allowProvisioningUpdates \
  ${auth[@]+"${auth[@]}"} \
  MARKETING_VERSION="$version" \
  CURRENT_PROJECT_VERSION="$build_number" \
  | tee "$out/archive.log" | grep -E "error:|warning: .*(sign|provision)|ARCHIVE (SUCCEEDED|FAILED)" || true
if [ ! -d "$archive" ]; then
  echo "release: archiving failed; see $out/archive.log" >&2
  exit 1
fi

destination="export"
if [ "$upload" -eq 1 ]; then
  destination="upload"
fi
cat >"$out/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key>
  <string>app-store-connect</string>
  <key>destination</key>
  <string>$destination</string>
  <key>teamID</key>
  <string>$team_id</string>
  <key>signingStyle</key>
  <string>automatic</string>
  <key>manageAppVersionAndBuildNumber</key>
  <false/>
</dict>
</plist>
PLIST

if [ "$upload" -eq 1 ]; then
  echo "Uploading to App Store Connect..."
else
  echo "Exporting..."
fi
if ! xcodebuild -exportArchive \
  -archivePath "$archive" \
  -exportOptionsPlist "$out/ExportOptions.plist" \
  -exportPath "$out/export" \
  -allowProvisioningUpdates \
  ${auth[@]+"${auth[@]}"} >"$out/export.log" 2>&1; then
  if grep -q "PLA Update available" "$out/export.log"; then
    echo "release: Apple has a new Program License Agreement; the account holder must accept it at https://developer.apple.com/account" >&2
  fi
  echo "release: export failed; see $out/export.log" >&2
  exit 1
fi

if [ "$upload" -eq 1 ]; then
  echo "Uploaded version $version build $build_number. It shows up in App Store Connect > TestFlight after processing (usually 10-30 minutes)."
else
  echo "Exported to $out/export"
fi
