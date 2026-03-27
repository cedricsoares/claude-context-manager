# claude-context-manager

Automated context management for Claude Code — never lose session context again.

## Overview

Claude Code sessions lose their context when conversations get too long or when you start a new session. `claude-context-manager` solves this by installing an automation layer that **automatically journals your work sessions** — decisions, progress, bugs, TODOs — without any manual intervention.

It builds on top of [mcp-memory-keeper](https://github.com/mkreyman/mcp-memory-keeper), adding hooks, a sub-agent, and skills that turn passive storage into active, automated context capture.

## Foundation: mcp-memory-keeper

This project depends on [mcp-memory-keeper](https://github.com/mkreyman/mcp-memory-keeper), an MCP server that provides persistent context management for Claude Code. Here's what it brings:

- **SQLite-based persistence** — all context is stored locally at `~/mcp-data/memory-keeper/`
- **Sessions** — track work across multiple conversations with named sessions
- **Channels** — topic-based organization, auto-derived from git branches (e.g., `feat/auth` → `feat-auth`)
- **Categories & priorities** — organize items by type (decision, progress, error, etc.) and importance
- **Full-text & semantic search** — find past context by keyword or meaning
- **Checkpoints** — snapshot and restore complete context states
- **Git integration** — automatic correlation with repository state
- **38 MCP tools** — save, get, search, batch operations, channels, relationships, and more

`mcp-memory-keeper` handles the *storage*. `claude-context-manager` handles the *automation* — detecting when something worth saving happens and structuring it properly.

Huge thanks to [@mkreyman](https://github.com/mkreyman) for building and maintaining `mcp-memory-keeper`. This project wouldn't exist without the solid foundation it provides.

## What this project adds

Four automation layers on top of the MCP server:

### Hook layer (`hooks/journal-trigger.sh`)

A bash script registered as a Claude Code `Stop` and `PreCompact` hook. It monitors session activity and triggers journaling only when meaningful events occur:

- **Write/Edit detection** — file modifications via Claude Code tools
- **Significant bash commands** — `git commit`, `terraform apply`, `dbt run`, `kubectl apply`, and more
- **PreCompact urgency** — saves context before Claude's context window gets compressed

Noise is filtered out: purely conversational sessions or minor formatting changes don't trigger anything.

### Sub-agent layer (`agents/journal.md`)

A Sonnet-powered agent that reads the session transcript and applies a **deterministic category taxonomy** to structure entries:

| Trigger | Category |
|---------|----------|
| Alternatives evaluated and one rejected | `decision` |
| Meaningful milestone reached | `progress` |
| Bug identified | `error` |
| Bug confirmed resolved | `root_cause` |
| Tests executed | `test_result` |
| TODO/FIXME/HACK in code | `todo` |
| Commit or explicit request | `session_end` |

Categories are never chosen freely — the situation determines the category. Every entry includes mandatory metadata: project, branch, and date.

### Skills layer (`skills/`)

Four session lifecycle protocols that structure how context is captured depending on the type of work:

| Skill | When | Focus |
|-------|------|-------|
| `memory-keeper-session` | Always loaded | Session init (MCP start, context restore) and closing (TODO grep, session_end) |
| `memory-keeper-feature` | Feature branches | Linear: investigate → implement → test → document |
| `memory-keeper-debug` | Bug investigations | Non-linear: symptom → hypotheses → dead ends → root cause |
| `memory-keeper-maintenance` | Refactors, migrations | Before/after state capture, rollback points |
| `memory-keeper-mixin` | Any sub-agent (opt-in) | Compact conventions for sub-agents to read/write memory-keeper |

### Multi-agent orchestration layer

When Claude Code orchestrates multiple sub-agents, the system provides three complementary mechanisms:

1. **`SubagentStop` hook** (`hooks/subagent-journal-trigger.sh`) — Universal safety net that fires when any sub-agent completes. Reads the sub-agent's own transcript, detects significant work, and triggers the journal agent. Works with any agent (custom or third-party) without modification.

2. **`memory-keeper-mixin` skill** — Compact conventions that any custom sub-agent can load via `skills: [memory-keeper-mixin]`. Enables direct read/write access to memory-keeper (semantic search before acting, structured saves during work).

3. **Orchestrator guidance** — Each workflow skill (debug, feature, maintenance) includes instructions for the orchestrator to pass memory-keeper context in sub-agent prompts, ensuring even agents without the mixin benefit from prior context.

## Architecture

```
Claude Code session
        │
        ▼
┌─────────────────────┐
│  Hook: Stop /       │   Reads session transcript,
│  PreCompact event   │   detects significant events
└────────┬────────────┘
         │ spawns (async)
         ▼
┌─────────────────────┐
│  Sub-agent: journal │   Applies deterministic taxonomy,
│  (Sonnet model)     │   structures entries
└────────┬────────────┘
         │ MCP tool calls
         ▼
┌─────────────────────┐
│  mcp-memory-keeper  │   Persists to SQLite,
│  (MCP server)       │   indexes, searches
└────────┬────────────┘

Multi-agent flow (SubagentStop):

Claude Code session
  ├── spawns sub-agent A ──► work ──► SubagentStop hook fires
  │                                    ├── reads sub-agent transcript
  │                                    ├── detects significant work
  │                                    └── spawns journal agent ──► saves to MCP
  ├── spawns sub-agent B ──► work ──► SubagentStop hook fires
  │                                    └── (same flow)
  └── session ends ──► Stop hook fires
                        ├── detects 2+ Agent calls → "orchestrator"
                        └── spawns journal agent ──► saves synthesis
         │
         ▼
    ~/mcp-data/
    memory-keeper/
    context.db
```

## Prerequisites

- **Node.js** and **npx** — for running `mcp-memory-keeper`
- **python3** — for patching `~/.claude.json` and `settings.json`
- **jq** — for JSON parsing in hook scripts
- **Claude Code** — with hooks and sub-agent support

## Installation

```bash
git clone https://github.com/cedricsoares/claude-context-manager.git
cd claude-context-manager
bash install.sh
```

The installer is idempotent (safe to run multiple times) and performs these steps:

1. Checks prerequisites (node, npx, python3, jq)
2. Installs `mcp-memory-keeper` globally via npm (if not present)
3. Registers the MCP server in `~/.claude.json` (if not configured)
4. Copies skills (including `memory-keeper-mixin`) to `~/.claude/skills/`
5. Copies the journal sub-agent to `~/.claude/agents/` (+ example agents to `agents/examples/`)
6. Copies hook scripts (`journal-trigger.sh` + `subagent-journal-trigger.sh`) to `~/.claude/hooks/`
7. Patches `~/.claude/settings.json` with Stop, PreCompact, and SubagentStop hooks
8. Merges workflow instructions into `~/.claude/CLAUDE.md`

After installation, **restart Claude Code** to activate.

## Usage

### Branch names matter

The current git branch is the backbone of context organization. The system uses it to:

- **Derive the channel** — `mcp-memory-keeper` converts the branch name into a channel (e.g., `feat/ig-comments` → `feat-ig-comments`). All entries for that branch are grouped under this channel.
- **Build memory keys** — every saved entry includes a short form of the branch name in its key (e.g., `myproject_ig-comments_decision_auth-flow`), making entries searchable and traceable.
- **Restore context** — when you initialize a session, the branch name drives the semantic search queries that retrieve past decisions, progress, and TODOs.
- **Isolate contexts** — switching branches means switching context. Each branch has its own TODOs, decisions, and progress. Coming back to a branch restores its full history.

Use descriptive branch names (`feat/user-auth`, `fix/api-timeout`, `refactor/db-schema`) — the more meaningful the name, the better the context retrieval.

### Starting a session

At the beginning of each Claude Code session, ask Claude to initialize:

> "Initialize the session"

This triggers the `memory-keeper-session` skill, which:
- Starts an MCP session linked to the current git branch
- Searches for existing context from previous sessions on this branch
- Restores TODOs, recent progress, and past decisions
- Outputs a summary of where you left off

### Declaring the session type

On the first session for a new branch, Claude will ask:

> "Is this a feature, bugfix, or maintenance session?"

This loads the appropriate skill, which adapts how context is captured:
- **Feature** — tracks architecture decisions, implementation milestones, test results
- **Debug** — tracks symptoms, hypotheses (including dead ends), and root cause
- **Maintenance** — tracks before/after state, rollback points, impact

### During work

**Automatic journaling** happens in the background via hooks. When Claude stops after modifying files or running significant commands, the journal sub-agent captures what happened. You don't need to do anything.

**Manual saves** are also possible at any time:

> "Save this decision"
> "Journal this progress"
> "Remember that we rejected approach X because..."

### Multi-agent sessions

When Claude Code orchestrates multiple sub-agents, the system captures their work automatically via the `SubagentStop` hook. No manual intervention needed — each sub-agent's transcript is analyzed and journaled independently.

To give a custom sub-agent direct access to memory-keeper, add to its frontmatter:

```yaml
---
name: my-agent
skills:
  - memory-keeper-mixin
mcpServers:
  - memory-keeper
---
```

See `agents/examples/debug-investigator.md` for a complete example.

Third-party agents work without modification — the `SubagentStop` hook captures their work as a safety net.

### Closing a session

Session closing is **automatic on `git commit`** — the hook detects the commit, greps TODOs from modified files, and saves a `session_end` entry with what was done, what's blocked, and the next step.

You can also close manually:

> "Close the session"

### Resuming work

When you start a new Claude Code session on the same branch, just initialize again. The system restores your full context: decisions, progress, open TODOs, and where you left off.

```
## Session Start — my-project / feat/new-api
Date: 2025-06-15

### Current state
API endpoint scaffolded, auth middleware integrated, tests pending.

### Open TODOs
- [high] Add rate limiting before merge
- [normal] Update API docs

### Next step
Write integration tests for /api/v2/users
```

## Verification

```bash
# Check the sub-agent is registered
claude agents | grep journal

# Check hooks are configured
cat ~/.claude/settings.json | jq '.hooks'

# Test the PreCompact hook manually
echo '{"hook_event_name":"PreCompact","trigger":"manual","transcript_path":"","cwd":"'"$PWD"'","stop_hook_active":false}' \
  | bash ~/.claude/hooks/journal-trigger.sh
```

## Uninstallation

```bash
rm ~/.claude/agents/journal.md
rm ~/.claude/hooks/journal-trigger.sh
rm ~/.claude/hooks/subagent-journal-trigger.sh
rm ~/.claude/skills/memory-keeper-mixin.md
rm -rf ~/.claude/agents/examples/
rm ~/.claude/skills/memory-keeper-*.md
# Restore settings.json backup if needed
ls ~/.claude/settings.json.backup-*
```

The `mcp-memory-keeper` MCP server and its data (`~/mcp-data/memory-keeper/`) are left intact — remove them separately if desired.

## License

[MIT](LICENSE)
