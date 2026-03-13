---
phase: quick-1
plan: 1
subsystem: n8n-inbound-workflow
tags: [n8n, evolution-api, messages-set, onboarding, supabase]
dependency_graph:
  requires: []
  provides: [MESSAGES_SET event handler in inbound workflow]
  affects: [workflows/sdr-gatekeeper-inbound.json]
tech_stack:
  added: []
  patterns: [n8n IF node routing, Supabase executeQuery with continueRegularOutput]
key_files:
  created: []
  modified:
    - workflows/sdr-gatekeeper-inbound.json
decisions:
  - "MESSAGES_SET intercepted before Parse Evolution Payload to avoid false 'not_message_event' ignore in parse node"
  - "onError: continueRegularOutput used so Supabase failures never block or error the webhook response"
  - "IF false output routes to Parse Evolution Payload preserving 100% of existing flow for all other events"
metrics:
  duration: "5 minutes"
  completed: "2026-03-13"
  tasks_completed: 1
  files_modified: 1
---

# Quick Task 1: Add MESSAGES_SET Handler to Inbound Workflow Summary

**One-liner:** IF node intercepts MESSAGES_SET before parse, routing to a silent Supabase UPDATE that marks sf_clinics onboarding_status as sync_complete.

## What Was Done

Added two nodes to `workflows/sdr-gatekeeper-inbound.json` to handle the Evolution API `MESSAGES_SET` event, which fires when WhatsApp reconnects or syncs history:

1. **"É MESSAGES_SET?" (IF node)** — inserted at position [480, 500], between "Webhook - Evolution API" and "Parse Evolution Payload". Checks `$json.body.event === 'MESSAGES_SET'` (case-sensitive, strict).

2. **"Supabase - Sync Onboarding (MESSAGES_SET)" (Postgres node)** — at position [700, 500], executes:
   ```sql
   UPDATE sf_clinics
   SET onboarding_status = 'sync_complete', onboarding_step = 3
   WHERE evolution_instance_id = '{{ $json.body.instance }}'
   AND onboarding_status = 'pending'
   ```
   Configured with `onError: continueRegularOutput` so failures are silent.

## Connection Changes

| Before | After |
|--------|-------|
| Webhook → Parse Evolution Payload | Webhook → É MESSAGES_SET? |
| (no handler for MESSAGES_SET) | IF true → Supabase UPDATE → (end) |
| | IF false → Parse Evolution Payload (unchanged) |

## Deviations from Plan

None — plan executed exactly as written.

## Self-Check: PASSED

- [x] `check-messages-set` node present in JSON
- [x] `sync-onboarding-messages-set` node present in JSON
- [x] `onError: continueRegularOutput` set on Supabase node
- [x] Webhook connects to "É MESSAGES_SET?" (not directly to Parse Evolution Payload)
- [x] IF output[0] (true) → Supabase - Sync Onboarding (MESSAGES_SET)
- [x] IF output[1] (false) → Parse Evolution Payload
- [x] JSON is valid and parseable
- [x] Commit 146193e exists
