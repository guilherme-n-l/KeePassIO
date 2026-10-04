{
  description = "KeePassIOS development shell";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs =
    {
      nixpkgs,
      flake-utils,
      ...
    }:
    # Intel macOS is left out: nixpkgs-unstable no longer supports it.
    flake-utils.lib.eachSystem [ "aarch64-darwin" "x86_64-linux" "aarch64-linux" ] (
      system:
      let
        pkgs = import nixpkgs { inherit system; };
        inherit (pkgs) lib;
        inherit (pkgs.stdenv.hostPlatform) isDarwin isLinux;
      in
      {
        # mkShellNoCC: no Nix C compiler or Apple SDK in the environment, so on
        # macOS xcodebuild, xcrun and swift keep using the installed Xcode.
        devShells.default = pkgs.mkShellNoCC {
          packages =
            with pkgs;
            [
              git
              nixfmt # scripts/lint.sh formats flake.nix
              shellcheck # scripts/lint.sh, .githooks
              nodejs # markdownlint-cli2 via npx in scripts/lint.sh
              python3 # scripts/flash.sh, CI helpers
              keepassxc # keepassxc-cli for the KeePassXC interop tests
            ]
            ++ lib.optionals isDarwin [
              swiftlint # swift and swift-format come from Xcode
            ]
            ++ lib.optionals isLinux [
              bpftrace # Tools/bpf probes
              zlib # headers for the vendored KDBXKit
              pkg-config
            ];

          shellHook = ''
            # A shell from another Nix environment may have pointed these at a
            # Nix SDK; Xcode's own tools must win for app builds.
            unset DEVELOPER_DIR SDKROOT

            # Git hooks and merge policy, same as scripts/bootstrap.sh.
            if [ -x scripts/bootstrap.sh ]; then
              scripts/bootstrap.sh >/dev/null
            fi

            ${
              if isDarwin then
                ''
                  if ! command -v xcodebuild >/dev/null 2>&1; then
                    echo "keepassios: install Xcode for swift, swift-format and xcodebuild" >&2
                  fi
                ''
              else
                ''
                  if ! command -v swift >/dev/null 2>&1; then
                    echo "keepassios: no Swift toolchain on PATH; run sudo scripts/setup-linux-toolchain.sh" >&2
                  fi
                ''
            }
          '';
        };
      }
    );
}
