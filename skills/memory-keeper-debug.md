---
name: memory-keeper-debug
description: "Handles memory-keeper tracking for bug investigation and fix sessions. Load this skill when session_type is 'debug' or 'bugfix'. Covers: symptom capture, hypothesis tracking, root cause documentation, and cleanup of invalidated hypotheses. Fundamentally different from feature workflow: non-linear, investigation-first, synthesis at resolution."
---

# Memory-Keeper Debug Skill

This skill structures memory-keeper usage for debug and bugfix sessions.
Always loaded alongside `memory-keeper-session` which handles init and closing.

---

## When to use this skill

Session type declared as `debug` or `bugfix`, covering:
- Production bugs
- Unexpected behavior
- Pipeline failures
- API response anomalies
- Performance issues
- Data quality problems

---

## Key difference from feature workflow

Feature workflow is linear: investigate → implement → test → document.
Debug workflow is non-linear: symptom → multiple hypotheses → dead ends → root cause.

**Do not save dead ends as `progress`.** Save them as `hypothesis` with result `invalidated`.
Only the confirmed root cause becomes a permanent entry.

---

## Step 1 — Search existing memory-keeper before investigating

Before starting any investigation, use semantic search to find similar past issues.
Natural language search is more effective here than category filtering.

```
mcp_context_semantic_search({
  query: 'bugs similar to {symptom description}',
  topK: 5,
  minSimilarity: 0.4
})

mcp_context_semantic_search({
  query: 'root cause {component or error type}',
  topK: 3,
  minSimilarity: 0.5
})
```

Also check by category for exact matches:
```
mcp_context_get({ category: 'root_cause', channel: '{project}' })
mcp_context_get({ category: 'error', channel: '{project}' })
```

If a similar `root_cause` exists: read it first and check if applicable.
**This step is mandatory — do not skip it, even for seemingly unique bugs.**

---

## Step 2 — Capture the symptom

As soon as the bug is identified, save before any investigation begins:

```
key:      {project}_{branch-short}_error_{slug}
category: error
channel:  {project}
priority: high
value:
  project:    {project}
  branch:     {branch}
  date:       {YYYY-MM-DD}
  symptom:    {exact error message or observed behavior}
  context:    {when does it happen, under what conditions}
  first_seen: {commit or date when it appeared}
  affected:   {what is impacted}
```

**Trigger**: automatic as soon as a bug is identified, before any investigation.

---

## Step 3 — Track hypotheses (do not pollute progress)

For each hypothesis tested:

```
key:      {project}_{branch-short}_hypothesis_{slug}
category: hypothesis
channel:  {project}
priority: normal
value:
  project:    {project}
  branch:     {branch}
  date:       {YYYY-MM-DD}
  hypothesis: {what was assumed}
  test:       {how it was tested}
  result:     validated | invalidated
  finding:    {what was learned, even if invalidated}
```

**Rules:**
- Save every hypothesis, including invalidated ones — the finding has value
- Never convert an invalidated hypothesis to a `progress` entry
- Invalidated hypotheses can be deleted after `root_cause` is confirmed if they add no long-term value

---

## Step 4 — Confirm root cause

When the bug is fully understood and fixed:

```
key:      {project}_{branch-short}_root_cause_{slug}
category: root_cause
channel:  {project}
priority: high
value:
  project:      {project}
  branch:       {branch}
  date:         {YYYY-MM-DD}
  symptom:      {exact symptom from error entry}
  root_cause:   {confirmed explanation}
  fix_applied:  {what was changed}
  files:
    - {modified file}: {what changed}
  commit:       {commit hash and message}
  tested:       {how the fix was validated}
  prevention:   {how to avoid this in the future — optional}
```

**This is the only entry that matters long-term. Everything else is investigation scaffolding.**

---

## Step 5 — Cleanup after resolution

After saving `root_cause`:
- Review `hypothesis` entries for this branch
- Delete invalidated hypotheses that have no standalone learning value
- Keep invalidated hypotheses only if the finding itself is reusable

---

## TODO Detection in Debug Sessions

TODOs in debug sessions typically come from:
- Fixes that are partial ("this stops the crash but doesn't address the underlying cause")
- Related issues discovered during investigation but out of scope
- Prevention measures identified but not yet implemented

Same format as feature TODOs — one entry per branch, overwritten at each commit.

---

## Debug Session End Entry

At commit or explicit close:

```
key:      {project}_{branch-short}_session_end_{YYYY-MM-DD}
category: session_end
channel:  {project}
priority: high
value:
  project:           {project}
  branch:            {branch}
  date:              {YYYY-MM-DD}
  commit:            {commit hash and message}
  status:            resolved | in_progress | blocked
  root_cause:        {one line summary if resolved}
  hypotheses_tested: {count}
  next_step:         {exact next action}
  open_todos:        {count} items remaining
```

---

## Anti-patterns to avoid

- Saving every investigation step as `progress` — use `hypothesis` instead
- Claiming a bug is fixed without a confirmed `root_cause` entry
- Deleting `error` entries after resolution — they are permanent reference
- Starting investigation without semantic search on existing `root_cause` entries
- Using `context_get` with category filter instead of `context_semantic_search` for similarity search
