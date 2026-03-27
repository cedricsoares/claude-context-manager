---
name: memory-keeper-mixin
description: "Compact memory-keeper conventions for sub-agents. Load this skill in any agent that should read from or write to memory-keeper. Provides key format, taxonomy, metadata rules, and instructions for context search before acting."
---

# Memory-Keeper Mixin for Sub-Agents

You have access to the `mcp-memory-keeper` MCP server. Use it to read prior context before working and to save your findings as you go.

---

## Step 1 — Read before acting

Before starting any work, search for relevant prior context:

```
mcp__memory-keeper__context_semantic_search({
  query: "{describe the problem or task in generic terms}",
  topK: 3
})
```

If results are found, incorporate them into your analysis. Do not repeat work that was already done.

---

## Step 2 — Save findings using deterministic taxonomy

When you produce significant findings, save them immediately. **The category is determined by the situation, never chosen freely.**

| Situation | Category |
|-----------|----------|
| Multiple approaches evaluated, one rejected | `decision` |
| Significant milestone reached | `progress` |
| Bug identified | `error` |
| Hypothesis tested (valid or invalidated) | `hypothesis` |
| Bug confirmed resolved | `root_cause` |
| Tests executed | `test_result` |

**Do not save if**: nothing significant happened, changes are minor (formatting, typos), or the work is purely conversational.

---

## Key format

```
{project}_{branch-short}_{category}_{slug}
```

- `{project}`: repository name or directory name
- `{branch-short}`: 3-4 significant words from the branch in kebab-case
- `{slug}`: 2-3 descriptive words in kebab-case

Example: `my-api_fix-auth-null_hypothesis_middleware-check`

---

## Mandatory metadata in every entry

Every value saved to memory-keeper must begin with:

```
project:      {project}
branch:       {branch}
date:         {YYYY-MM-DD}
source_agent: {your agent name}
---
```

The `source_agent` field identifies which agent produced this entry.

---

## Entry formats

**decision:**
```
question:  {what was decided}
chosen:    {chosen approach}
rejected:
  - {option}: {reason}
rationale: {why this choice}
```

**error:**
```
symptom:    {exact message or behavior}
context:    {when does it happen}
affected:   {what is impacted}
```

**hypothesis:**
```
hypothesis: {what was assumed}
test:       {how it was tested}
result:     validated | invalidated
finding:    {what was learned}
```

**root_cause:**
```
symptom:     {original symptom}
root_cause:  {confirmed explanation}
fix_applied: {what was changed}
tested:      {how the fix was validated}
```

**progress:**
```
status: {what works now}
next:   {what remains}
```

**test_result:**
```
parameters: {exact parameters}
result:     success | failure | partial
output:     {relevant lines only}
next:       {action based on result}
```

---

## Rules

- **Channel**: always use the project name as channel
- **No secrets**: save variable names (`SECRET_NAME`), never values
- **No noise**: do not save if nothing significant happened
- **No raw output**: extract only the relevant lines
- **Batch save**: use `context_batch_save` for multiple entries, `context_save` for a single one
