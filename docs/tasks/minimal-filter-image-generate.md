# Task: Minimal Filter — Show image_generate + sessions_spawn tool_start, conditional results

**Date:** 2026-06-02
**Status:** completed

## Goal

The minimal filter should show:
1. `tool_start` of `image_generate` and `sessions_spawn` — always visible so user sees the prompt/task
2. `tool_result` of `image_generate` — ONLY when `status: completed` (hides intermediate/running/failed states)
3. `tool_result` of `sessions_spawn` — with `childSessionKey` badge in tr-header, clickable to switch sessions

Other tools' `tool_result` events remain unfiltered (shown as before).

## Changes

### `index.html`
- **Line 1781:** Minimal filter now also shows `tool_start` for `sessions_spawn`
- **Line 3036:** New `renderSpawnResult` function — renders `childSessionKey` in tr-header as:
  - Clickable badge (via `showSession()`) when the session exists in the sidebar
  - Non-clickable muted badge when the session doesn't exist
- **Line 3863:** Added `case 'sessions_spawn':` to `renderToolResult` dispatch
- **Line 512:** Added `sessions_spawn` to `_expandedItems` (auto-expand results)

### `docs/ui-components.md`
- **Line 136:** Update the minimal filter description

### `docs/event-types-reference.md`
- **Line ~392:** Update minimalist view description
