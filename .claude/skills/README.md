# Vendored Claude skills

Third-party [Agent Skills](https://docs.claude.com/en/docs/claude-code/skills) copied into this repository so every Claude session on it loads them. Only each skill's name and description load up front; the body and references load when a task needs them.

They are vendored, not written here: don't edit them except for the local changes listed below, and exclude them from our linters. To update one, re-copy it from the upstream commit and update this table.

| Skill | Purpose | Upstream (commit) | License |
|---|---|---|---|
| `swiftui-expert-skill` | SwiftUI architecture, state, layout, Liquid Glass, localization, performance; scripts to record and analyze Instruments traces | [AvdLee/SwiftUI-Agent-Skill](https://github.com/AvdLee/SwiftUI-Agent-Skill) `9897311` | MIT |
| `swiftui-pro` | SwiftUI review: modern APIs, design, accessibility, performance | [twostraws/SwiftUI-Agent-Skill](https://github.com/twostraws/SwiftUI-Agent-Skill) `be297ff` | MIT |
| `swift-concurrency` | Swift 6 strict concurrency: actors, Sendable, tasks, migration | [AvdLee/Swift-Concurrency-Agent-Skill](https://github.com/AvdLee/Swift-Concurrency-Agent-Skill) `d577081` | MIT |
| `swift-testing-expert` | Swift Testing: `#expect`, traits, parameterized and async tests | [AvdLee/Swift-Testing-Agent-Skill](https://github.com/AvdLee/Swift-Testing-Agent-Skill) `798e9b1` | MIT |
| `test-driven-development` | Write the failing test first | [obra/superpowers](https://github.com/obra/superpowers) `8ca22db` | MIT |
| `systematic-debugging` | Find the root cause before proposing a fix | [obra/superpowers](https://github.com/obra/superpowers) `8ca22db` | MIT |
| `verification-before-completion` | Run the checks and show the output before claiming something works | [obra/superpowers](https://github.com/obra/superpowers) `8ca22db` | MIT |
| `caveman` | Opt-in terse reply mode to cut output tokens (`/caveman`, "stop caveman" to end) | [JuliusBrussee/caveman](https://github.com/JuliusBrussee/caveman) `6571943` | Apache-2.0 |

## Local changes

- Removed upstream logos, `agents/openai.yaml` and plugin manifests (not used by Claude Code).
- `systematic-debugging`: removed the upstream skill-evaluation fixtures (`test-*.md`, `CREATION-LOG.md`); rewrote `superpowers:<name>` references to the local skill names.
- `test-driven-development`: removed a reference to `superpowers:writing-skills`, which isn't vendored.
- Each skill folder keeps its upstream `LICENSE` (and `NOTICE` for `caveman`).

## Considered and left out

- `caveman-commit` and other caveman sub-skills: their terse commit style conflicts with this repo's commit message rules.
- Anthropic's `frontend-design`: web-focused, not SwiftUI.
- Having both SwiftUI skills overlaps somewhat; `swiftui-expert-skill` is the broader reference, `swiftui-pro` the compact review checklist. Drop one if they pull in conflicting directions.
