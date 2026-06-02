# Improve Tool Result Rendering — memory_search + web_fetch

**Created:** 2026-06-02
**Status:** completed

## Changes

### 1. `renderMemorySearchHeader` — Show query in header

**Problem:** Header shows `🔍 N results` but doesn't show what was searched for.
**Fix:** Look up matching `tool_start` via `_findToolStart(ev.toolCallId)` to extract `query` from input. Show it as `🔍 "query" · N results`.

**Code:** `index.html` `renderMemorySearchHeader` (line ~2631)

### 2. `renderWebFetchHeader` — New specialized renderer

**Problem:** `web_fetch` falls through to `renderGenericHeader` which just shows `↳ web_fetch` + code block body. No URL, duration, or content length in header. Body renders as generic code block.

**Fix:**
- Add new `renderWebFetchHeader(ev, parsed, t, idx, expanded)` function
- Header shows: `↳ web_fetch` tag + status code badge + shortened URL + duration in ms + content size
- When expanded: renders extracted text via `renderUdiffContent()` (same as read/write)
- Status code badge colored green (2xx) or red (4xx/5xx)
- Add `case 'web_fetch'` to the `renderToolResult` switch

**Code:** `index.html` — new function before `renderGenericHeader`, case in `renderToolResult` switch

### 3. `renderMemorySearchHeader` — Add query lookup (cleanup)

**Already done above** — the query lookup code is part of change 1.

## Result

Both `memory_search` and `web_fetch` tool results now show meaningful context in the header instead of just counts or generic tool names.
