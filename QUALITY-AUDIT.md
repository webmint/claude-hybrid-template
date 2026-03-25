# Quality Audit v2: AIDevTeamForge — Re-Audit After v1 Fixes

## Context

Re-audit of the AIDevTeamForge template system after all fixes from the v1 audit (2026-03-25) were applied. Covers all 15 commands, 5 templates, 14 agent templates, install.sh, update.sh, template-manifest.json, settings.template.json, and cross-file consistency.

---

## v1 Audit Status (31 issues)

All 31 issues from the v1 audit have been verified and resolved:

| ID | Issue | v1 Status | v2 Status |
|----|-------|-----------|-----------|
| C1 | Phase 8 auto-compact impossible | Open | **RESOLVED** — Phase 8 now pauses and asks user to run /compact |
| C2 | Constitution placeholder gap | Open | **RESOLVED** — Guard added to /specify, /plan, /breakdown, /execute-task, /fix, /refactor |
| C3 | Greenfield threshold conflict | Open | **RESOLVED** — All thresholds aligned (0-5/6+), project-config.json checked first |
| C4 | settings.local.json broken hook | RESOLVED (v1) | RESOLVED |
| C5 | git add -A risk | RESOLVED (v1) | RESOLVED |
| C6 | History rewrite | RESOLVED (v1) | RESOLVED |
| C7 | Universal rules lost | RESOLVED (v1) | RESOLVED |
| H1 | No test execution in pipeline | RESOLVED (v1) | RESOLVED |
| H2 | Agent assignment gaps | RESOLVED (v1) | RESOLVED |
| H3 | Memory format undefined | RESOLVED (v1) | RESOLVED |
| H4 | Branch/spec counter mismatch | RESOLVED (v1) | RESOLVED |
| H5 | /verify references /commit | RESOLVED (v1) | RESOLVED |
| H6 | Unlimited fix review cycles | RESOLVED (v1) | RESOLVED |
| H7 | Date format inconsistency | RESOLVED (v1) | RESOLVED |
| H8 | /onboard Phase 3.3 duplicate | RESOLVED (v1) | RESOLVED |
| M1 | No partial setup detection | Open | **RESOLVED** — setup-complete marker written by setup-wizard |
| M2 | Context load no budget | Open | **RESOLVED** — 500-line threshold added |
| M3 | Session-state size not enforced | Open | **RESOLVED** — verification step added |
| M4 | /fix /refactor no session-state | Open | **RESOLVED** — Phase 10 added to both |
| M5 | Wrapper isolation incomplete | Open | **RESOLVED** — bugs/, research/, .mcp.json added |
| M6 | Compaction contradiction | Open | **RESOLVED** — difference documented as intentional |
| M7 | Contracts not grep-verifiable | Open | **RESOLVED** — literal identifier guidance added |
| M8 | update.sh ## headers only | Open | **MOOT** — merge_sections() was dead code, now removed |
| M9 | /specify no git check | Open | **RESOLVED** — Phase 0.0 prerequisite added |
| M10 | Research filename format | Open | **RESOLVED** — YYYY-MM-DD format |
| L1 | Agent model undocumented | Open | **RESOLVED** — rationale in setup-wizard |
| L2 | install.sh copies settings.local | Open | **RESOLVED** — rm -f after copy |
| L3 | Unused spec template | Open | **RESOLVED** — removed |
| L4 | Research path mismatch | Open | **RESOLVED** — paths aligned |
| L5 | Ukrainian time hardcoded | Open | **RESOLVED** — removed |
| L6 | memory: project field unclear | Open | **RESOLVED** — removed |

---

## v2 New Issues Found (16 issues — all fixed)

### HIGH (3)

#### ~~N-H1. `install.sh` copies `release.md` to target projects~~ RESOLVED
- **Resolution**: install.sh now removes `.claude/commands/release.md` after the bulk copy. Target projects no longer get the template-repo-only `/release` command.

#### ~~N-H2. Type check/lint commands hardcoded to TypeScript/ESLint across multiple commands~~ RESOLVED
- **Resolution**: Added `Type Check Command` and `Lint Command` fields to `CLAUDE.template.md`. All commands (execute-task, fix, refactor, verify, breakdown) now reference "the Type Check Command from CLAUDE.md" and "the Lint Command from CLAUDE.md" instead of hardcoded `tsc --noEmit` / ESLint. Agent prompt templates updated to use generic "project's type checker/linter". `setup-wizard` updated with `TYPE_CHECK_COMMAND` and `LINT_COMMAND` in required keys and example config.

#### ~~N-H3. `settings.template.json` doesn't include Edit, Write, Bash, or Agent permissions~~ RESOLVED
- **Resolution**: Added `Edit`, `Write`, `Bash`, and `Agent` to the permissions allow list in `settings.template.json`. The workflow now functions without requiring dozens of manual permission approvals per task.

### MEDIUM (8)

#### ~~N-M1. `architect.template.md` has typo `Te/sting` on line 15~~ RESOLVED
- **Resolution**: Fixed to `Testing`.

#### ~~N-M2. `settings.template.json` references wrong context7 MCP tool name~~ RESOLVED
- **Resolution**: Changed `mcp__context7__get-library-docs` to `mcp__context7__query-docs` to match the current `@upstash/context7-mcp` tool name.

#### ~~N-M3. `/refactor` Phase 6 code review has no cycle cap~~ RESOLVED
- **Resolution**: Added "max 1 additional review cycle" cap matching `/fix`'s pattern. If still BLOCKED after one additional cycle, execution stops and reports to the user.

#### ~~N-M4. `CLAUDE.template.md` workflow diagram has misleading `(auto)` label~~ RESOLVED
- **Resolution**: Fixed label alignment. Each command now has its own correct label: `(per feat)` for /specify, /plan, /breakdown; `(per task)` for /execute-task; `(per feat)` for /verify.

#### ~~N-M5. `/verify` and `/clarify` lack constitution populated guard~~ RESOLVED
- **Resolution**: Added the `_Run /constitute to populate_` guard to both /verify Phase 1 and /clarify Phase 1, matching all other commands.

#### ~~N-M6. `/release` Phase 5 doesn't check `CLAUDE.template.md` or `storage-rules.md`~~ RESOLVED
- **Resolution**: Added Phase 5.5 to /release that checks if CLAUDE.template.md and storage-rules.md need updating when commands, workflows, or storage conventions change.

#### ~~N-M7. `install.sh` leaks template repo memory files to target projects~~ RESOLVED
- **Resolution**: install.sh now removes `.claude/memory/` after the bulk copy and recreates it empty. Setup-wizard recreates MEMORY.md from the template.

#### ~~N-M8. `execute-task.md` Phase 3.2 agent prompt is TypeScript/ESLint-specific~~ RESOLVED
- **Resolution**: Changed to "project's type checker" and "project's linter" (see N-H2).

### LOW (5)

#### ~~N-L1. `copyIfMissing` in manifest doesn't include `research/.gitkeep`~~ RESOLVED
- **Resolution**: Added `"research/.gitkeep"` to the `copyIfMissing` patterns in template-manifest.json.

#### N-L2. `.claude/setup-complete` marker is written but never consumed
- **Status**: ACCEPTED — The marker is cheap to write and provides a future hook point. Existing prerequisite checks (CLAUDE.md + agents exist) are sufficient for current commands.

#### ~~N-L3. `update.sh` contains ~100 lines of dead code (`merge_sections` function)~~ RESOLVED
- **Resolution**: Removed the dead `merge_sections()` Perl function and its comments from update.sh.

#### ~~N-L4. `/onboard` references "Task tool" in parentheses~~ RESOLVED
- **Resolution**: Removed "(Task tool)" parenthetical from onboard.md. Now consistently says "Agent tool".

#### ~~N-L5. No dedicated `Type Check Command` field in `CLAUDE.template.md`~~ RESOLVED
- **Resolution**: Added `Type Check Command` and `Lint Command` fields to the Project Overview section (see N-H2).

---

## Summary

| Category | Count | Status |
|----------|-------|--------|
| v1 issues | 31 | 30 RESOLVED, 1 MOOT |
| v2 HIGH | 3 | All RESOLVED |
| v2 MEDIUM | 8 | All RESOLVED |
| v2 LOW | 5 | 4 RESOLVED, 1 ACCEPTED |
| **TOTAL** | **47** | **All addressed** |

---

## Verification Checklist

After all fixes applied:

1. [x] `install.sh` — no `release.md` copied, no template memory files copied
2. [x] `CLAUDE.template.md` — has Type Check Command and Lint Command fields
3. [x] `settings.template.json` — has Edit, Write, Bash, Agent permissions; correct context7 tool name
4. [x] `architect.template.md` — no `Te/sting` typo
5. [x] All commands reference "Type Check Command from CLAUDE.md" — no hardcoded tsc/ESLint
6. [x] All commands have constitution populated guard — including /verify and /clarify
7. [x] `/release` — checks CLAUDE.template.md and storage-rules.md
8. [x] `/refactor` — review cycle capped at 1 additional cycle
9. [x] Workflow diagram — correct label alignment
10. [x] `template-manifest.json` — research/.gitkeep in copyIfMissing
11. [x] `update.sh` — dead merge_sections() code removed
12. [x] `onboard.md` — no "(Task tool)" references
