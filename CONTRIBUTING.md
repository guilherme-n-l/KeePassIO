# Contributing to KeePassIOS

KeePassIOS is MIT-licensed. Read [PLAN.md](PLAN.md) for the architecture and the decisions behind it.

## Setup

1. Install Xcode (16 or newer) and SwiftLint (`brew install swiftlint`). `swift-format` ships with the Xcode toolchain.
2. Install Node.js (for `markdownlint-cli2`, run through `npx`) and ShellCheck (`brew install shellcheck`).
3. Run `scripts/bootstrap.sh` once after cloning. It enables the git hooks in `.githooks/` and the merge policy below.

## Clean-room rule

KeePassium, KeePassXC and KeePassDX are GPL-licensed. Never copy, translate or paraphrase their code into this repository. Reading their behavior and the KDBX format documentation is fine; running `keepassxc-cli` as a test tool is fine.

## Lint and formatting

- `scripts/lint.sh` runs every check: swift-format, SwiftLint, markdownlint, ShellCheck and the code-comment rule below.
- `scripts/lint.sh --fix` applies formatting fixes first.
- The pre-commit hook runs the same checks on staged files, and CI runs them on the whole tree. Don't bypass hooks with `--no-verify`.
- If a tool is missing, the check fails rather than silently skipping.

## Code comments

Comments explain what the code does and why, in plain language. They never refer to the plan's phases, steps or milestones ("Phase 1", "Step 3", "M2"): those live in `PLAN.md` and go stale in code. The lint script rejects them.

## Commit messages

The commit-msg hook checks the format:

```text
Capitalized imperative subject, 72 characters or fewer, no period

Body explaining what changed and why: the problem, the approach, and
anything a reviewer should look at. Wrap at 72 characters.

Diagrams are welcome when they make a change clearer:

  app ──unlock──▶ DatabaseSession ──save──▶ NSFileCoordinator ──▶ file.kdbx
```

- Every commit needs a body, even a short one.
- Use ASCII diagrams in the body for flows, data layouts and before/after structure.
- Screenshots, GIFs and screen recordings of UI changes go in `docs/media/` (or in the pull request description) and are linked from the commit body by path.

## Branches and merging

- Work on a feature branch. Bring `main` into your branch with a merge commit (`git merge --no-ff main`), never a rebase or fast-forward. `scripts/bootstrap.sh` sets `merge.ff=false` so this is the default.
- Pull requests are merged into `main` with a merge commit (no squash, no rebase-merge).

## Reporting bugs and security issues

- Bugs: open an issue and attach a diagnostics export (Settings → Diagnostics → Export). Never attach a real database, key file or password.
- Security issues: see [SECURITY.md](SECURITY.md); don't open a public issue.
