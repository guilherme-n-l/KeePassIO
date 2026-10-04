# Notes for Claude

Follow [CONTRIBUTING.md](CONTRIBUTING.md) and [PLAN.md](PLAN.md). The rules the owner set explicitly:

- **Commit messages** are clear and explain what was done and why, with ASCII diagrams in the body where they help. Screenshots, GIFs and recordings go in `docs/media/` or the pull request and are linked.
- **Code comments** are normal prose about the code. No "Phase 1", "Step A", "M2" or other plan references in code.
- **Lint and formatting** pass before every commit: run `scripts/lint.sh` (use `--fix` to format).
- **Hooks run before every commit.** Run `scripts/bootstrap.sh` in a fresh clone; never commit with `--no-verify`.
- **Merges create merge commits.** Bring `main` into a branch with `git merge --no-ff`; no fast-forward, no rebase onto `main`.
- **Subagents are allowed** for parallel or exploratory work.
- **Handroll only when necessary**; prefer maintained MIT/BSD/Apache/CC0 dependencies (PLAN.md section 9b). For performance-critical code, prefer Rust over C over assembly, and only when profiling justifies it (section 9c).

## Environment notes

- The cloud container is Linux without a Swift toolchain (download.swift.org is blocked by its network policy), so Swift code can't be built, formatted or linted here; the owner builds on their Mac and CI checks everything.
