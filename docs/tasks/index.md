# Task Index

This file tracks all tasks, features, and changes made to the DeepClaw UI project.

## Planned Tasks

_(none)_

## Completed Tasks

- **[dynamic-agent-list-in-modal](dynamic-agent-list-in-modal.md)** (2026-06-01) — Replaced hardcoded agent dropdown in "Start New Session" modal with dynamic list fetched from `/api/agents`. Backend now returns `sessionKey` for each agent; frontend caches list on WS open and populates on modal open.

- **[fix-sessions-create-reason-field](fix-sessions-create-reason-field.md)** (2026-06-01) — Fixed "Start new session" dialog failing after gateway updated `sessions.changed` payload from `state` to `reason` field.
- **[add-download-button-to-viewer](add-download-button-to-viewer.md)** (2026-05-31) — Client-side Download button in file viewer tabs (code + markdown). Uses Blob from embedded page content for instant download without re-fetching.
- **[agent-specific-theming](agent-specific-theming.md)** (2026-05-31) — Subtle per-agent accent color theming. Each agent gets a deterministic hue from the blue-purple range (225-255°) applied via CSS `--accent` variable on session switch. Persisted in localStorage.
- **[fix-agent-tool-events](fix-agent-tool-events.md)** (2026-05-31) — Fixed tool events not rendering after OpenClaw v2026.5.28 update. Tools now arrive via `agent` event (not `session.tool`) when deepclaw-ui is registered as a `toolEventRecipient`.

---

*Add new tasks by creating files in this directory. Update this index after each task completes.*
