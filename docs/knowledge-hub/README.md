# Knowledge hub — lessons for the next session

One lesson per file, named `YYYY-MM-DD-<slug>.md`. Record corrections and confirmed approaches
alike, with why they mattered — a lesson is only useful with its reason. Don't save what the
repository already records: the schema rules belong in `README.md` / `AGENTS.md`, and a change's
tx digests and reasons belong in its commit message and PR, as they already are. Update an
existing note rather than adding a near-duplicate; delete a note proven wrong.

Agents: scan the titles (`grep -h '^title:' docs/knowledge-hub/*.md`) before touching an
unfamiliar package block, and add a note at the end of a task when something cost real time
that the next session would otherwise rediscover (a consumer that broke on a shape change, a
field a parser silently dropped).

## Shape

Every field and section is defined in the shared schema, `Bucket-Protocol/waterx-commons`
`knowledge-hub/SCHEMA.md` — the same one the `data-infra` and `bucket-backend-mono` hubs follow,
so the hubs read as one set.

```markdown
---
title: "<the lesson in one sentence: what breaks, or what to do>"
date: "YYYY-MM-DD"
domain: "engineering"
knowledge_type: "error"            # error | decision | pattern
source: "ai-agent"                 # human | ai-agent
source_agent: "Claude Code"        # tool name when source is ai-agent, else ""
project: "waterx-config"
tags: [mainnet, withdrawal-queue]
roles: [Backend]                   # Backend | Frontend | DevOps | DataEngineer | Contracts | Product
error_type: config                 # config | deploy | build | runtime | data (error entries)
severity: high                     # low | medium | high | critical
verification_command: "jq .packages.withdrawal_queue.queues.USD mainnet.json"
affected_files: ["mainnet.json"]
related_errors: []                 # slugs of other entries
---

## Problem

## Root cause

## Resolution

## Prevention
```
