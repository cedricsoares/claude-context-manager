# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**memory-keeper-hooks** is a Claude Code extension that adds automatic journaling via hooks and a sub-agent on top of the `memory-keeper-workflow` plugin. It is **not a standalone application** — it extends an existing MCP server (`mcp-memory-keeper`) by installing Claude Code hooks, skills, and a sub-agent into `~/.claude/`.

The project is written in English.

## Architecture

The system has three layers that work together:

1. **Hook layer** (`hooks/journal-trigger.sh`) — A bash script registered as a Claude Code `Stop` and `PreCompact` hook. It reads the JSON payload from stdin, parses the session transcript to detect significant events (Write/Edit tools or significant bash commands like `git commit`, `terraform apply`), and spawns the journal sub-agent only when meaningful work occurred.

2. **Sub-agent layer** (`agents/journal.md`) — A Sonnet-powered agent that receives trigger context (event type, transcript path, cwd) and applies deterministic category taxonomy to save structured entries via `mcp-memory-keeper` MCP tools. Categories are never chosen freely — the trigger type determines the category.

3. **Skills layer** (`skills/`) — Four markdown skills injected into `~/.claude/skills/` that define session lifecycle protocols:
   - `memory-keeper-session.md` — Always loaded. Handles session init (MCP session start, semantic search, context restore) and closing (TODO grep, session_end save).
   - `memory-keeper-feature.md` — For feature branches. Linear workflow: investigate → implement → test.
   - `memory-keeper-debug.md` — For bugfix branches. Non-linear: symptom → hypotheses → root cause. Dead ends saved as `hypothesis`, not `progress`.
   - `memory-keeper-maintenance.md` — For refactors/migrations. Focus on before/after state and rollback points.

**Data flow**: Claude Code event → `journal-trigger.sh` (filters noise) → spawns `claude -p` with journal agent → agent reads transcript tail → applies taxonomy → calls `mcp-memory-keeper` MCP tools to persist.

## Installation

```bash
bash install.sh
```

The installer is idempotent and performs 8 steps:
1. Checks prerequisites (node, npx, python3, jq)
2. Verifies/installs `mcp-memory-keeper` npm package globally
3. Registers MCP server in `~/.claude.json` if missing
4. Copies skills to `~/.claude/skills/`
5. Copies journal agent to `~/.claude/agents/`
6. Copies hook script to `~/.claude/hooks/`
7. Patches `~/.claude/settings.json` with Stop/PreCompact hooks (via `hooks/patch-settings.py`)
8. Merges workflow instructions into `~/.claude/CLAUDE.md` (via `claude-md-patch/merge.sh`)

## Key Design Decisions

- **Hook filtering is intentionally strict**: `journal-trigger.sh` exits silently unless Write/Edit tools or significant bash commands (git commit, terraform, dbt, kubectl, etc.) were detected. This prevents noise from purely conversational sessions.
- **`--dangerously-skip-permissions`** is used when spawning the journal sub-agent because it runs asynchronously after the user's session ends.
- **Category taxonomy is deterministic**: The agent prompt explicitly forbids free category choice. The trigger/situation determines the category (e.g., `decision` only when alternatives were evaluated and rejected).
- **CLAUDE.md patching uses markers**: `claude-md-patch/merge.sh` uses `# --- memory-keeper-workflow START/END ---` markers to support idempotent updates without destroying other CLAUDE.md content.
- **One TODO entry per branch**: Overwritten on each commit, never duplicated. Empty list saved as `items: []`, never deleted.

## File Purposes

| File | Target | Purpose |
|------|--------|---------|
| `install.sh` | — | Orchestrates full installation |
| `agents/journal.md` | `~/.claude/agents/` | Sub-agent prompt with taxonomy rules |
| `hooks/journal-trigger.sh` | `~/.claude/hooks/` | Event detection and agent spawning |
| `hooks/patch-settings.py` | — | Patches settings.json (run once) |
| `claude-md-patch/merge.sh` | — | Idempotent CLAUDE.md section merger |
| `claude-md-patch/patch.md` | — | Content block injected into CLAUDE.md |
| `skills/*.md` | `~/.claude/skills/` | Session lifecycle protocols |

## Development Notes

- All installed files target `~/.claude/` — this repo is a source/distribution, not a runtime directory.
- The hook script resolves the `claude` binary by checking multiple known paths before falling back to `$PATH`.
- `patch-settings.py` creates a timestamped backup of `settings.json` before modification.
- When modifying the journal agent prompt, remember that category assignments must remain deterministic — test by verifying the taxonomy table matches the trigger conditions.

<!-- rtk-instructions v2 -->
# RTK (Rust Token Killer) - Token-Optimized Commands

## Golden Rule

**Always prefix commands with `rtk`**. If RTK has a dedicated filter, it uses it. If not, it passes through unchanged. This means RTK is always safe to use.

**Important**: Even in command chains with `&&`, use `rtk`:
```bash
# Wrong
git add . && git commit -m "msg" && git push

# Correct
rtk git add . && rtk git commit -m "msg" && rtk git push
```

## RTK Commands by Workflow

### Build & Compile (80-90% savings)
```bash
rtk cargo build         # Cargo build output
rtk cargo check         # Cargo check output
rtk cargo clippy        # Clippy warnings grouped by file (80%)
rtk tsc                 # TypeScript errors grouped by file/code (83%)
rtk lint                # ESLint/Biome violations grouped (84%)
rtk prettier --check    # Files needing format only (70%)
rtk next build          # Next.js build with route metrics (87%)
```

### Test (90-99% savings)
```bash
rtk cargo test          # Cargo test failures only (90%)
rtk vitest run          # Vitest failures only (99.5%)
rtk playwright test     # Playwright failures only (94%)
rtk test <cmd>          # Generic test wrapper - failures only
```

### Git (59-80% savings)
```bash
rtk git status          # Compact status
rtk git log             # Compact log (works with all git flags)
rtk git diff            # Compact diff (80%)
rtk git show            # Compact show (80%)
rtk git add             # Ultra-compact confirmations (59%)
rtk git commit          # Ultra-compact confirmations (59%)
rtk git push            # Ultra-compact confirmations
rtk git pull            # Ultra-compact confirmations
rtk git branch          # Compact branch list
rtk git fetch           # Compact fetch
rtk git stash           # Compact stash
rtk git worktree        # Compact worktree
```

Note: Git passthrough works for ALL subcommands, even those not explicitly listed.

### GitHub (26-87% savings)
```bash
rtk gh pr view <num>    # Compact PR view (87%)
rtk gh pr checks        # Compact PR checks (79%)
rtk gh run list         # Compact workflow runs (82%)
rtk gh issue list       # Compact issue list (80%)
rtk gh api              # Compact API responses (26%)
```

### JavaScript/TypeScript Tooling (70-90% savings)
```bash
rtk pnpm list           # Compact dependency tree (70%)
rtk pnpm outdated       # Compact outdated packages (80%)
rtk pnpm install        # Compact install output (90%)
rtk npm run <script>    # Compact npm script output
rtk npx <cmd>           # Compact npx command output
rtk prisma              # Prisma without ASCII art (88%)
```

### Files & Search (60-75% savings)
```bash
rtk ls <path>           # Tree format, compact (65%)
rtk read <file>         # Code reading with filtering (60%)
rtk grep <pattern>      # Search grouped by file (75%)
rtk find <pattern>      # Find grouped by directory (70%)
```

### Analysis & Debug (70-90% savings)
```bash
rtk err <cmd>           # Filter errors only from any command
rtk log <file>          # Deduplicated logs with counts
rtk json <file>         # JSON structure without values
rtk deps                # Dependency overview
rtk env                 # Environment variables compact
rtk summary <cmd>       # Smart summary of command output
rtk diff                # Ultra-compact diffs
```

### Infrastructure (85% savings)
```bash
rtk docker ps           # Compact container list
rtk docker images       # Compact image list
rtk docker logs <c>     # Deduplicated logs
rtk kubectl get         # Compact resource list
rtk kubectl logs        # Deduplicated pod logs
```

### Network (65-70% savings)
```bash
rtk curl <url>          # Compact HTTP responses (70%)
rtk wget <url>          # Compact download output (65%)
```

### Meta Commands
```bash
rtk gain                # View token savings statistics
rtk gain --history      # View command history with savings
rtk discover            # Analyze Claude Code sessions for missed RTK usage
rtk proxy <cmd>         # Run command without filtering (for debugging)
rtk init                # Add RTK instructions to CLAUDE.md
rtk init --global       # Add RTK to ~/.claude/CLAUDE.md
```

## Token Savings Overview

| Category | Commands | Typical Savings |
|----------|----------|-----------------|
| Tests | vitest, playwright, cargo test | 90-99% |
| Build | next, tsc, lint, prettier | 70-87% |
| Git | status, log, diff, add, commit | 59-80% |
| GitHub | gh pr, gh run, gh issue | 26-87% |
| Package Managers | pnpm, npm, npx | 70-90% |
| Files | ls, read, grep, find | 60-75% |
| Infrastructure | docker, kubectl | 85% |
| Network | curl, wget | 65-70% |

Overall average: **60-90% token reduction** on common development operations.
<!-- /rtk-instructions -->
