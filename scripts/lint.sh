#!/usr/bin/env bash
# Runs every linter and formatter check used by the pre-commit hook and CI.
#
#   scripts/lint.sh            check all tracked files
#   scripts/lint.sh --staged   check only files staged for commit
#   scripts/lint.sh --fix      apply formatting fixes, then check
#
# A check is skipped only when no file of its type is selected. If files of a
# type are selected and the tool for them is missing, the script fails: no
# file reaches a commit without being checked.
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

mode="all"
fix=0
for arg in "$@"; do
  case "$arg" in
    --staged) mode="staged" ;;
    --fix) fix=1 ;;
    *) echo "unknown argument: $arg" >&2; exit 2 ;;
  esac
done

# Vendored third-party files keep their upstream formatting and are not linted.
vendored='^(\.claude/skills/[^/]+/|Vendor/)'

list_files() {
  local pattern="$1"
  if [[ "$mode" == "staged" ]]; then
    git diff --cached --name-only --diff-filter=ACMR -- "$pattern"
  else
    git ls-files -- "$pattern"
  fi | { grep -Ev "$vendored" || true; }
}

failed=0
fail() { echo "lint: $*" >&2; failed=1; }

require() {
  if ! command -v "$1" >/dev/null 2>&1; then
    fail "$1 is required to check $2 files but is not installed (see CONTRIBUTING.md)"
    return 1
  fi
}

swift_format() {
  if command -v swift-format >/dev/null 2>&1; then
    swift-format "$@"
  elif command -v xcrun >/dev/null 2>&1 && xcrun --find swift-format >/dev/null 2>&1; then
    xcrun swift-format "$@"
  else
    return 127
  fi
}

# SwiftLint's Linux build needs SourceKit from the Swift toolchain for some
# rules, including the custom ones in .swiftlint.yml.
if [[ "$(uname -s)" == "Linux" && -z "${LINUX_SOURCEKIT_LIB_PATH:-}" ]] && command -v swift >/dev/null 2>&1; then
  LINUX_SOURCEKIT_LIB_PATH="$(dirname "$(readlink -f "$(command -v swift)")")/../lib"
  export LINUX_SOURCEKIT_LIB_PATH
fi

# Plain read loops instead of mapfile: macOS ships bash 3.2, which lacks it.
swift_files=()
while IFS= read -r file; do swift_files+=("$file"); done < <(list_files '*.swift')
md_files=()
while IFS= read -r file; do md_files+=("$file"); done < <(list_files '*.md')
sh_files=()
while IFS= read -r file; do sh_files+=("$file"); done < <(list_files '*.sh'; list_files '.githooks/*')
source_files=()
while IFS= read -r file; do source_files+=("$file"); done < <(
  list_files '*.swift'
  list_files '*.rs'
  list_files '*.c'
  list_files '*.h'
)

if ((${#swift_files[@]})); then
  if ((fix)); then
    swift_format format --in-place --parallel "${swift_files[@]}" \
      || fail "swift-format is required to format Swift files but is not installed"
  fi
  swift_format lint --strict --parallel "${swift_files[@]}" \
    || fail "swift-format reported problems (or is not installed)"
  if require swiftlint Swift; then
    if ((fix)); then swiftlint lint --fix --quiet -- "${swift_files[@]}" || true; fi
    swiftlint lint --strict --quiet -- "${swift_files[@]}" || fail "SwiftLint reported problems"
  fi
fi

if ((${#md_files[@]})); then
  if require npx Markdown; then
    md_args=()
    ((fix)) && md_args+=(--fix)
    # ${md_args[@]+...} keeps bash 3.2 from treating an empty array as unset.
    npx --yes markdownlint-cli2@0.23.3 ${md_args[@]+"${md_args[@]}"} "${md_files[@]}" \
      || fail "markdownlint reported problems"
  fi
fi

if ((${#sh_files[@]})); then
  if require shellcheck shell; then
    shellcheck "${sh_files[@]}" || fail "shellcheck reported problems"
  fi
fi

# Code comments describe what the code does, not when it was planned.
# Plan references such as "Phase 1", "Step 3" or "M2" belong in PLAN.md.
if ((${#source_files[@]})); then
  if grep -nE '(//|/\*|^[[:space:]]*\*|#).*\b((Phase|Step|Stage|Milestone|Part) +([0-9]+|[A-Z])|M[0-9])\b' \
      "${source_files[@]}"; then
    fail "remove planning references (Phase/Step/Milestone) from code comments"
  fi
fi

exit "$failed"
