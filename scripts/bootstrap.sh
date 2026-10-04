#!/usr/bin/env bash
# One-time setup for a fresh clone: enables the repo's git hooks and merge
# policy. Run it once after cloning.
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

git config core.hooksPath .githooks
# Every merge creates a merge commit; fast-forward merges are never used.
git config merge.ff false
git config pull.rebase false
git config pull.ff false

echo "Hooks enabled from .githooks; merges always create a merge commit."
