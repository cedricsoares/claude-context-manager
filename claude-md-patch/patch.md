# --- memory-keeper-workflow START ---
# Memory-Keeper Workflow

## Session Initialization — Mandatory

At the start of every session, before any work, execute these steps IN THIS EXACT ORDER:

**1. Start session**
```
mcp__memory-keeper__context_session_start({
  name: "{project} — {branch}",
  projectDir: "{absolute path to repo root}",
  defaultChannel: "{project}"
})
```

**2. Read git context — always, used to build semantic queries**
```bash
git branch --show-current
git log --oneline -5
```

**3. Semantic search — TWO queries, both mandatory**

Query A — specific: retrieve context for this exact branch
```
mcp__memory-keeper__context_semantic_search({
  query: "{keywords extracted from branch name + last 3 commit messages}",
  topK: 3
})
```

Query B — abstract: retrieve similar patterns from other branches/projects
```
mcp__memory-keeper__context_semantic_search({
  query: "{functional problem described in generic terms, without network/project names}",
  topK: 3
})
```
Example: branch `feat-cso-tiktok-carousel-fix`, commits mention "item_type field missing"
- Query A: `"tiktok carousel item_type field missing collection"`
- Query B: `"API field missing data ingestion pipeline fix"`

❌ Do NOT use `context_search` or `context_search_all` — keyword matching only, misses related entries.
✅ If both queries return no results → proceed, do not compensate with more git exploration.

**4. Read structured context**
```
mcp__memory-keeper__context_get({ key: "{project}_{branch-short}_todo" })
mcp__memory-keeper__context_get({ category: "progress", channel: "{project}", limit: 3 })
mcp__memory-keeper__context_get({ category: "decision", channel: "{project}", limit: 5 })
```

**5. Git diff — only if memory-keeper returned fewer than 3 items total**
```bash
git diff --stat HEAD~1 HEAD
```

**6. Output this exact summary format — MANDATORY, never skip:**
```
## Session Start — {project} / {branch}
Date: {YYYY-MM-DD}

### État actuel
{3-5 lignes — basé sur context_get progress/decision}

### Commits récents
{git log -5 — toujours présent}

### Patterns similaires trouvés
{résultats Query B — autres branches/projets pertinents, ou "Aucun"}

### TODOs ouverts
{liste ou "Aucun"}

### Prochaine étape
{action concrète ou "À définir — quel type de session ?"}
```
Then load skill `memory-keeper-session` for session type detection and closing protocol.

## Session Closing — On every commit

Execute these steps IN THIS EXACT ORDER after every commit:

**1. Grep TODOs from committed files**
```bash
git diff HEAD~1 HEAD --name-only | xargs grep -n "TODO\|FIXME\|HACK" 2>/dev/null
```

**2. Update TODO entry — overwrite, do not duplicate**
```
mcp__memory-keeper__context_save({
  key: "{project}_{branch-short}_todo",
  category: "todo",
  channel: "{project}",
  priority: "high",
  value: "branch: {branch}\nupdated: {YYYY-MM-DD}\nitems:\n  - [high] {item}\n  (or 'items: []' if none)"
})
```

**3. Save session_end entry**
```
mcp__memory-keeper__context_save({
  key: "{project}_{branch-short}_session_end_{YYYY-MM-DD}",
  category: "session_end",
  channel: "{project}",
  priority: "high",
  value: "project: {project}\nbranch: {branch}\ndate: {YYYY-MM-DD}\ncommit: {hash} — {message}\ndone:\n  - {item}\nblocked:\n  - {item or none}\nnext_step: {exact next action}"
})
```

**4. Context protection — if context > 70%**
```
mcp__memory-keeper__context_prepare_compaction()
```
Then notify: "Context is at 70%+. Compaction checkpoint saved. Consider starting a fresh session."

## Memory-Keeper Rules

### Channel convention
Always use the project name as the channel: `channel: {project_name}`

### Key naming convention
```
{project}_{branch-short}_{category}_{slug}
```
Examples:
- `brut-social_ig-comments_decision_subflow-architecture`
- `brut-infra_grant-cloudsql_todo`
- `brut-social_ig-comments_root-cause_persisted-result`

### Mandatory metadata in every entry
```
project: {project_name}
branch:  {branch_name}
date:    {YYYY-MM-DD}
---
{content}
```

### Category taxonomy — deterministic, not Claude's free judgment

| Category | Trigger |
|---|---|
| `decision` | Automatic — alternatives were evaluated and rejected |
| `progress` | Automatic — meaningful milestone reached |
| `todo` | Automatic — code tag or user declaration |
| `error` | Automatic — bug identified |
| `hypothesis` | Automatic — debug sessions only |
| `root_cause` | Automatic — bug confirmed resolved |
| `test_result` | Automatic — after any test run |
| `session_end` | On commit or explicit user request |
| `backlog` | On explicit user mention only |
| `session_type` | Once per branch, first session only |

**Claude never chooses the category freely. The trigger defines the category.**

## TODO Rules

### Sources
1. Code tags: `# TODO`, `# FIXME`, `# HACK` in modified files
2. User declarations: "later", "skip for now", "to verify", "check before merging"

### Format — one entry per branch, overwritten at each commit
```
key:      {project}_{branch-short}_todo
category: todo
priority: high
value:
  branch:  {branch_name}
  updated: {YYYY-MM-DD}
  items:
    - [high] {item}
    - [normal] {item}
```

## Skill Routing

Load the appropriate skill based on session type declared at branch start:

| Session type | Skill to load |
|---|---|
| Feature / new implementation | `memory-keeper-feature` |
| Bug investigation / fix | `memory-keeper-debug` |
| Refactor / migration / dependency | `memory-keeper-maintenance` |

`memory-keeper-session` is always loaded regardless of session type.

## Context Monitoring — Proactive

After every 10 exchanges OR after any sequence of 3+ bash/file operations in a row,
proactively ask the user:

> "La session est longue — veux-tu que je sauvegarde et clôture avant de continuer ?"

If the user says yes → execute Session Closing protocol immediately.
If the user says no → continue, ask again after 10 more exchanges.

Do NOT wait for the user to ask. This check is Claude's responsibility.

- Never `cat` long files without `head`/`tail`
- Pipe long outputs: `| tail -50` or `| grep pattern`
- For logs: extract only ERROR/WARNING relevant lines
- Save summaries to memory-keeper, never raw output
- If context exceeds 70%: save `session_end` immediately and warn the user
# --- memory-keeper-workflow END ---
