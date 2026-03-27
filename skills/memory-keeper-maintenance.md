---
name: memory-keeper-maintenance
description: "Handles memory-keeper tracking for maintenance sessions: refactoring, migrations, dependency updates, configuration changes, and technical debt resolution. Load this skill when session_type is 'maintenance'. Focus on before/after state capture, rollback points, and impact documentation."
---

# Memory-Keeper Maintenance Skill

This skill structures memory-keeper usage for maintenance sessions.
Always loaded alongside `memory-keeper-session` which handles init and closing.

---

## When to use this skill

Session type declared as `maintenance`, covering:
- Refactoring (without behavior change)
- Dependency updates
- Infrastructure migrations
- Configuration changes
- Technical debt resolution
- Performance optimization
- Schema evolution

---

## Key difference from feature and debug workflows

Maintenance work changes existing behavior in controlled ways.
The critical risk is regression — something that worked stops working.

**Priority: capture before/after state at every significant step.**
**Every destructive or irreversible operation requires a checkpoint entry first.**

---

## Step 1 — Capture baseline state

Before any change, document the current state:

```
key:      {project}_{branch-short}_baseline_{slug}
category: progress
channel:  {project}
priority: high
value:
  project:   {project}
  branch:    {branch}
  date:      {YYYY-MM-DD}
  scope:     {what is being changed}
  before:
    behavior:  {how it works now}
    files:     {key files involved}
    version:   {dependency versions if applicable}
  risk:      {what could break}
  rollback:  {how to revert if needed}
```

**Trigger**: mandatory before starting any maintenance session.

---

## Step 2 — Track significant changes

For each meaningful change (not every line edit):

```
key:      {project}_{branch-short}_progress_{slug}
category: progress
channel:  {project}
priority: high
value:
  project:  {project}
  branch:   {branch}
  date:     {YYYY-MM-DD}
  changed:
    - {file or component}: {what changed and why}
  behavior: {same|modified — describe if modified}
  tested:   {how the change was validated}
  next:     {what remains}
```

---

## Step 3 — Architecture decisions during maintenance

If the maintenance reveals a structural decision (e.g. "use for_each instead of count"):

Same `decision` format as feature skill — with alternatives considered and rejected.

---

## Step 4 — Mandatory checkpoint before destructive operations

Before any of these operations, save a checkpoint:
- Deleting resources (Terraform destroy, DROP TABLE, etc.)
- Renaming or moving critical files
- Changing authentication or IAM configuration
- Updating major dependency versions
- Modifying shared infrastructure

```
key:      {project}_{branch-short}_checkpoint_{slug}
category: progress
channel:  {project}
priority: high
value:
  project:   {project}
  branch:    {branch}
  date:      {YYYY-MM-DD}
  operation: {what is about to happen}
  before:    {exact current state}
  rollback:  {exact steps to revert}
  risk:      {what could go wrong}
```

**Do not proceed with the operation until this entry is saved.**

---

## Step 5 — Validation after change

After each significant change is complete:

```
key:      {project}_{branch-short}_test_{slug}
category: test_result
channel:  {project}
priority: high
value:
  project:    {project}
  branch:     {branch}
  date:       {YYYY-MM-DD}
  scope:      {what was tested}
  parameters: {test parameters or validation method}
  result:     success | failure | partial
  behavior:   same as before | changed — describe
  next:       {what to do based on result}
```

---

## TODO Detection in Maintenance Sessions

Maintenance often reveals adjacent debt. Capture it without scope creep:
- If fixable in this session: do it, add to `progress`
- If out of scope: save as `backlog` entry, not `todo`
- `todo` entries in maintenance are for incomplete tasks in the current scope only

---

## Maintenance Session End Entry

```
key:      {project}_{branch-short}_session_end_{YYYY-MM-DD}
category: session_end
channel:  {project}
priority: high
value:
  project:        {project}
  branch:         {branch}
  date:           {YYYY-MM-DD}
  commit:         {commit hash and message}
  scope_done:     {what was changed}
  scope_remaining: {what is not yet done}
  regressions:    none | {describe if any}
  next_step:      {exact next action}
  open_todos:     {count} items remaining
  backlog_added:  {count} items added to backlog
```

---

## Multi-Agent Maintenance Sessions

When orchestrating multiple sub-agents for maintenance work:

### Before spawning sub-agents

The orchestrator must share critical context in the sub-agent's prompt:
- The `baseline` entry (before state, rollback plan) — sub-agents must know what they can break
- Any `checkpoint` entries saved before destructive operations
- `progress` entries showing what has already been changed

**Critical**: never let a sub-agent perform a destructive operation (delete, rename, major version bump) without first saving a `checkpoint` entry at the orchestrator level.

### Sub-agent configuration

For custom sub-agents you control:
```yaml
skills:
  - memory-keeper-mixin      # conventions for reading/writing
mcpServers:
  - memory-keeper             # reuses parent's MCP connection
```

For third-party agents: no modification needed. The `SubagentStop` hook captures their work automatically.

### After sub-agent returns

1. Verify that `test_result` entries confirm no regression
2. Check if `progress` entries document before/after state for each change
3. If the sub-agent revealed adjacent debt: save as `backlog`, not `todo`
4. If context exceeds 70%: run `context_prepare_compaction` before spawning another sub-agent

---

## Anti-patterns to avoid

- Starting destructive operations without a checkpoint entry
- Saving scope creep as `progress` — use `backlog` for adjacent debt
- Not testing after each significant change
- Claiming maintenance is complete without a passing `test_result`
- Letting a sub-agent perform destructive operations without an orchestrator-level checkpoint
