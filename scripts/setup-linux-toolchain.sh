#!/usr/bin/env bash
# Installs the Swift toolchain, swift-format, SwiftLint and bpftrace on Linux (Ubuntu
# 24.04, x86_64) so the core packages can be built, tested and linted. Used
# by Claude cloud sessions and Linux CI; macOS gets these tools from Xcode
# and Homebrew instead. Safe to run repeatedly: installed tools are skipped.
set -euo pipefail

if [[ "$(uname -s)" != "Linux" ]]; then
  exit 0
fi

swift_version="6.3.3"
swiftlint_version="0.65.1"
prefix="/opt/swift"
bin_dir="/usr/local/bin"

if [[ ! -x "$prefix/usr/bin/swift" ]] || ! "$prefix/usr/bin/swift" --version 2>/dev/null | grep -q "$swift_version"; then
  echo "Installing Swift $swift_version into $prefix"
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT
  curl -sSfL -o "$tmp/swift.tgz" \
    "https://download.swift.org/swift-$swift_version-release/ubuntu2404/swift-$swift_version-RELEASE/swift-$swift_version-RELEASE-ubuntu24.04.tar.gz"
  rm -rf "$prefix"
  mkdir -p "$prefix"
  tar -xzf "$tmp/swift.tgz" -C "$prefix" --strip-components=1
fi

for tool in swift swiftc swift-format; do
  ln -sf "$prefix/usr/bin/$tool" "$bin_dir/$tool"
done

# The dynamically linked build is used because the static one can't load
# SourceKit, and SwiftLint then silently skips SourceKit-based rules.
if ! swiftlint version 2>/dev/null | grep -qx "$swiftlint_version" || ! ldd "$bin_dir/swiftlint" >/dev/null 2>&1; then
  echo "Installing SwiftLint $swiftlint_version"
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT
  curl -sSfL -o "$tmp/swiftlint.zip" \
    "https://github.com/realm/SwiftLint/releases/download/$swiftlint_version/swiftlint_linux_amd64.zip"
  unzip -q -o "$tmp/swiftlint.zip" -d "$tmp/swiftlint"
  install -m 755 "$tmp/swiftlint/swiftlint" "$bin_dir/swiftlint"
fi

if ! command -v shellcheck >/dev/null 2>&1; then
  echo "Installing ShellCheck"
  pip install --quiet shellcheck-py
fi

if ! command -v bpftrace >/dev/null 2>&1 && command -v apt-get >/dev/null 2>&1; then
  echo "Installing bpftrace"
  apt-get install -y -q bpftrace >/dev/null
fi

echo "Swift $(swift --version 2>/dev/null | head -1 | sed 's/.*version \([^ ]*\).*/\1/'), swift-format, SwiftLint $(swiftlint version), ShellCheck ready."
