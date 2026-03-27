---
name: memory-keeper-feature
description: "Handles memory-keeper tracking for feature development and new implementation sessions. Load this skill when session_type is 'feature'. Covers: architecture decisions, implementation progress, test results, and checkpoint management throughout the feature lifecycle."
---

# Memory-Keeper Feature Skill

This skill structures memory-keeper usage for feature development sessions.
Always loaded alongside `memory-keeper-session` which handles init and closing.

---

## When to use this skill

Session type declared as `feature` at branch start, covering:
- New feature implementation
- New pipeline or flow creation
- API integration
- Schema changes
- New infrastructure components

---

## Checkpoint Protocol

### On architecture investigation
Before writing any code, if multiple approaches were considered:

```
key:      {project}_{branch-short}_decision_{slug}
category: decision
channel:  {project}
priority: high
value:
  project:    {project}
  branch:     {branch}
  date:       {YYYY-MM-DD}
  question:   {what was decided}
  chosen:     {chosen approach}
  rejected:
    - {rejected option}: {reason}
  rationale:  {why this choice}
```

**Trigger**: automatic whenever alternatives were evaluated and rejected.
**Do not save** a `decision` entry if only one approach was considered.

### On meaningful implementation milestone
```
key:      {project}_{branch-short}_progress_{slug}
category: progress
channel:  {project}
priority: high
value:
  project:  {project}
  branch:   {branch}
  date:     {YYYY-MM-DD}
  files:
    - {modified file}: {what changed}
  status:   {what works now}
  next:     {what remains}
```

**Trigger**: automatic at each meaningful milestone — not at every code line.
A milestone is: a component works end-to-end, a sub-task is complete, a blocker is resolved.

### Before any destructive operation or major refactor
Save a checkpoint entry before proceeding:

```
key:      {project}_{branch-short}_checkpoint_{slug}
category: progress
channel:  {project}
priority: high
value:
  project:  {project}
  branch:   {branch}
  date:     {YYYY-MM-DD}
  before:   {description of current state before the change}
  planned:  {what is about to be modified}
```

### After any test run
```
key:      {project}_{branch-short}_test_{slug}
category: test_result
channel:  {project}
priority: high
value:
  project:    {project}
  branch:     {branch}
  date:       {YYYY-MM-DD}
  parameters: {exact test parameters used}
  result:     {success|failure}
  output:     {relevant output lines — not raw dump}
  next:       {what to do based on result}
```

**Trigger**: automatic after every test run, whether passing or failing.
**Never claim a feature is complete without saving a passing test_result entry.**

---

## TODO Detection Rules

### From code
At each commit, grep modified files:
```bash
git diff HEAD~1 HEAD --name-only | xargs grep -n "TODO\|FIXME\|HACK" 2>/dev/null
```

### From user declarations in chat
Detect and save as TODO when user says:
- "we'll handle that later"
- "skip for now"
- "to verify"
- "check this before merging"
- "not in scope for this PR"

### Format
One single entry per branch, overwritten at each commit (see `memory-keeper-session`).

---

## Backlog Detection

When user mentions technical debt or improvements explicitly out of scope:

```
key:      {project}_backlog_{slug}
category: backlog
channel:  {project}
priority: normal
value:
  project:    {project}
  date:       {YYYY-MM-DD}
  source_branch: {branch}
  item:       {description}
  rationale:  {why deferred}
```

**Trigger**: only on explicit user mention. Claude does not infer backlog items.

---

## Multi-Agent Feature Sessions

When orchestrating multiple sub-agents for a feature implementation:

### Before spawning sub-agents

The orchestrator must share relevant context from memory-keeper in the sub-agent's prompt:
- Architecture `decision` entries already made (to avoid re-debating settled choices)
- `progress` entries showing what is already built
- `test_result` entries showing what has been validated

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

1. Check if `decision` or `progress` entries were saved by the sub-agent
2. Verify that implementation choices are consistent with prior decisions
3. If context exceeds 70%: run `context_prepare_compaction` before spawning another sub-agent

---

## Feature Completion Checklist

Before closing a feature session as complete, verify:
- [ ] At least one passing `test_result` entry saved
- [ ] All `decision` entries saved for architecture choices made
- [ ] `todo` entry updated (or empty)
- [ ] `session_end` entry saved with next_step
- [ ] No unsaved `# TODO` / `# FIXME` in committed files
