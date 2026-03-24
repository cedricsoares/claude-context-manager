---
name: memory-keeper-session
description: "Handles session initialization and closing for all Claude Code work sessions. Triggered automatically at session start and at each commit. Load this skill regardless of session type (feature, debug, maintenance). Handles: starting the MCP session, reading existing context from memory-keeper, reconciling TODOs from code and chat, summarizing current state, and writing session_end entries on commit."
---

# Memory-Keeper Session Skill

This skill handles the two mandatory bookends of every work session: initialization and closing.
It is always loaded first, regardless of the session type (feature, debug, maintenance).

---

## Session Initialization

### Step 1 — Start MCP session
Use the native MCP call to initialize the session. This derives the channel automatically
from the current git branch, and registers the session in the database.

```
mcp_context_session_start({
  name: '{project} — {branch}',
  projectDir: '{absolute path to repo root}',
  defaultChannel: '{project}'   ← fallback if git branch is unavailable
})
```

This replaces manual git bash for project/branch/channel detection.
The channel is auto-derived from the branch name (e.g. `feat/ig-comments` → `feat-ig-comments`).

### Step 2 — Read memory-keeper (sequential, stop if context > 20%)

**CALL THESE TOOLS IN THIS EXACT ORDER. NO SUBSTITUTIONS.**

❌ FORBIDDEN at init: `context_search`, `context_search_all`, `git log`, glob patterns
✅ REQUIRED: `context_semantic_search` → then `context_get` calls below

**2a — Semantic search (ALWAYS first, NO exceptions)**
```
mcp__memory-keeper__context_semantic_search({
  query: "{describe current branch work in plain language}",
  topK: 5
})
```
Use the branch name and known feature context to build the query.
Example: branch `feat-cso-instagram-backfill-comments` → query `"Instagram comments backfill windowing Prefect flow"`

**2b — TODO entry**
```
mcp__memory-keeper__context_get({
  key: "{project}_{branch-short}_todo"
})
```

**2c — Last 3 progress entries**
```
mcp__memory-keeper__context_get({
  category: "progress",
  channel: "{project}",
  limit: 3
})
```

**2d — Last 5 decision entries**
```
mcp__memory-keeper__context_get({
  category: "decision",
  channel: "{project}",
  limit: 5
})
```

**2e — Only if session_type is `debug`**
```
mcp__memory-keeper__context_get({ category: "error", channel: "{project}" })
mcp__memory-keeper__context_get({ category: "root_cause", channel: "{project}" })
```

Stop immediately if context consumption exceeds 20% at any point in this sequence.

**If all Step 2 calls return empty:**
- This is normal for a new branch or first session on a project
- Do NOT fall back to `git log`, `git diff`, or glob patterns to compensate
- Proceed directly to Step 3 (TODO grep) and Step 4 (summary)
- In the Step 4 summary, state clearly: "No existing context for this branch — starting fresh"
- git log and file exploration are only allowed if the user explicitly asks for them after init

**If only some calls return empty:**
- Continue the sequence, skip empty results silently
- Build the summary from whatever was found

### Step 3 — Reconcile TODOs
```bash
# Grep code tags in modified and tracked files
git diff HEAD --name-only | xargs grep -n "TODO\|FIXME\|HACK" 2>/dev/null
git ls-files --modified | xargs grep -n "TODO\|FIXME\|HACK" 2>/dev/null
```

Merge results with the memory-keeper TODO entry.
Display the unified list before starting work.

### Step 4 — State summary
Output a summary in this format before any work begins:

```
## Session Start — {project} / {branch}
Type: {feature|debug|maintenance}
Date: {YYYY-MM-DD}

### Current state
{5 lines max summarizing where we are}

### Open TODOs
- [high] {item}
- [normal] {item}

### Last decision
{1 line}

### Next step
{exact next action}
```

### Step 5 — Session type
If no `session_type` entry exists for this branch, ask:
> "Is this a feature, bugfix, or maintenance session?"

Save the response:
```
key:      {project}_{branch-short}_session_type
category: session_type
channel:  {project}
priority: normal
value:
  project: {project}
  branch:  {branch}
  date:    {YYYY-MM-DD}
  type:    {feature|debug|maintenance}
```

Then load the corresponding skill:
- feature      → `memory-keeper-feature`
- debug/bugfix → `memory-keeper-debug`
- maintenance  → `memory-keeper-maintenance`

---

## Session Closing — Triggered at each commit

### Step 1 — Grep TODOs from committed files
```bash
git diff HEAD~1 HEAD --name-only | xargs grep -n "TODO\|FIXME\|HACK" 2>/dev/null
```

### Step 2 — Update TODO entry
Overwrite (do not duplicate) the single TODO entry for this branch:
```
key:      {project}_{branch-short}_todo
category: todo
channel:  {project}
priority: high
value:
  project: {project}
  branch:  {branch}
  updated: {YYYY-MM-DD}
  items:
    - [high] {item from code grep or user declaration}
    - [normal] {item}
```

If no TODOs remain, save the entry with `items: []` — do not delete it.

### Step 3 — Save session_end entry
```
key:      {project}_{branch-short}_session_end_{YYYY-MM-DD}
category: session_end
channel:  {project}
priority: high
value:
  project:    {project}
  branch:     {branch}
  date:       {YYYY-MM-DD}
  commit:     {commit hash and message}
  done:
    - {completed item}
  blocked:
    - {blocked item and reason}
  next_step:  {exact next action}
  open_todos: {count} items remaining
```

### Step 4 — Context protection
If context consumption exceeds 70% at any point during the session,
use the native MCP compaction helper instead of a manual save:

```
mcp_context_prepare_compaction()
```

This automatically: creates a checkpoint, identifies high-priority items,
captures unfinished tasks, saves all decisions, and prepares restoration instructions.

Then notify the user:
> "Context is at 70%+. Compaction checkpoint saved. Consider starting a fresh session."
