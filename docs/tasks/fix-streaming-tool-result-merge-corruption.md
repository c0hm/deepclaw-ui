# Fix: Streaming tool_result merge corrupts JSON envelopes

**Date:** 2026-06-02
**Status:** Done ✅
**Completed:** 2026-06-02
**Refined:** 2026-06-02 (two-path architecture, agent stream, edge cases)

## Problem

During real-time streaming, tool results sometimes render as raw JSON dumps instead of formatted diffs/cards. The same session data loaded from disk (via sidebar switch or page reload) renders correctly.

**Affected tools:** ALL tools whose final result is a JSON envelope with `details`:
`read`, `write`, `edit`, `exec`, `process`, `memory_search`, `update_plan`,
`image_generate`, `message`, `video_generate`, `music_generate`.

Specifically, any tool whose result renderer at `renderToolResult()` dispatches on `parsed.details` — when `parsed.details` is `null`, all per-tool renderers fall through to generic raw-text rendering.

**Reproduction:** While actively streaming, observe tool results. "Sometimes" raw JSON appears. Switching sessions in the sidebar fixes it for the same events.

## Root Cause

Two conflicting merge strategies for streaming tool results — one in the backend (on disk) and one in the frontend (streaming) — produce different event representations.

### Architecture: two paths produce tool results in the frontend

Events reach the browser through two independent paths:

**Path 1 — Raw `session.tool`** (`index.html` §6, `handleGatewayMsg`, branch at L1461):
- Backend `broadcastToClients(msg)` forwards the raw gateway message to all browsers.
- Frontend handles `session.tool` directly:
  - `phase === 'start'`: pushes new `tool_start` event
  - `phase === 'done' || phase === 'result'`: pushes new `tool_result` event
  - `phase === 'update'`: updates `tool_start.status` (does NOT create tool_result)

**Path 2 — Converted `event.added`** (`index.html` §6, `handleGatewayMsg`, branch at L1060):
- Backend `convertToFrontendEvent()` converts ALL phases (`update`, `result`, `done`) into `tool_result` events.
- Backend `addEvent()` stores them in SessionState with dedup, then broadcasts as `event.added`.
- Frontend `event.added` handler merges streaming tool_result events by **blind string concatenation** (L1100-1116).

Both paths fire for every `session.tool` gateway event. The raw path creates tool_results for `done`/`result` phases; the `event.added` path creates tool_results for all phases including `update`.

### Backend (correct): stores intermediate + final as separate events

`deepclaw-ui.js` L887-898 — `SessionState._makeEventKey()` includes `hashString(result)` in the dedup key. When the gateway sends both `phase: 'update'` (partial) and `phase: 'done'` (final) for the same tool call, the different result hashes produce different keys → both events stored separately in `sess.events[]`.

```javascript
// deepclaw-ui.js L896
if (ev.result) parts.push(hashString(typeof ev.result === 'string' ? ev.result : JSON.stringify(ev.result)));
```

### Frontend (bug): concatenates them into one corrupted event

`index.html` L1100-1116 — `event.added` handler merges streaming tool_result events by blind concatenation:

```javascript
prev.result += resultStr;  // ← concatenation
```

### How corruption happens (most common sequence)

Gateway sends for an `edit` tool call:

1. `phase: 'update'` → partial text: `"Applying edit to /path/to/file...\n"`
2. `phase: 'done'` → JSON envelope:
   ```json
   {"content":[{"type":"text","text":"Edit applied"}],"details":{"patch":"@@ ...","diff":"..."}}
   ```

After frontend concatenation in `event.added` handler:
```
"Applying edit to /path/to/file...\n{\"content\":[{\"type\":\"text\",\"text\":\"Edit applied\"}],\"details\":{\"patch\":\"@@ ...\"}}"
```

This is **not valid JSON**. `parseToolResult()` fails → returns `{text: "...", details: null}` → all per-tool renderers that depend on `parsed.details` fall through to generic raw-text rendering.

### Why loaded data works

`fetchSessionHistory()` → `GET /api/session/:key` loads events from disk as **separate array entries**. The final event's `result` is valid JSON → `parseToolResult` succeeds → renders correctly.

### Why "sometimes"

- **Fast synchronous tools:** Gateway sends only `phase: 'done'` → no intermediate update event → no merge → works
- **Slower tools / tools with streaming output:** Gateway sends `phase: 'update'` then `phase: 'done'` → merge corrupts JSON → fails

## Fix: Option A (frontend-only)

**File:** `index.html`

**Location:** `handleGatewayMsg()` → `event.added` handler → tool_result merge block (near L1100-1116)

**Strategy:** Instead of blindly concatenating, detect whether the incoming result is a complete JSON envelope. If it is, **replace** the previous result entirely (the final `done` result supersedes any intermediate text). If it's not a JSON envelope (e.g., exec stdout partial), **append** as before.

### Change 1: Add helper function

Add `tryParseToolResultEnvelope(str)` near `parseToolResult()` (L2117, Section 13 in `index.html`):

```javascript
function tryParseToolResultEnvelope(str) {
  try {
    const obj = typeof str === 'string' ? JSON.parse(str) : str;
    if (obj && typeof obj === 'object' && Array.isArray(obj.content)) {
      return obj;
    }
    return null;
  } catch {
    return null;
  }
}
```

### Change 2: Smart merge in `event.added` handler

Replace the blind concatenation at the tool_result merge block:

```javascript
// Merge streaming tool_result events
if (ev.type === 'tool_result' && ev.runId) {
  const resultStr = typeof ev.result === 'string' ? ev.result : JSON.stringify(ev.result);
  for (let i = sess.events.length - 1; i >= 0; i--) {
    const prev = sess.events[i];
    if (prev.type === 'tool_result' && prev.toolCallId === ev.toolCallId && prev.runId === ev.runId) {
      // If new result is a complete JSON envelope, it supersedes any
      // intermediate partial text — replace, don't concatenate.
      // Plain text results (e.g., exec stdout deltas) are still appended.
      if (tryParseToolResultEnvelope(resultStr)) {
        prev.result = resultStr;
        prev.isError = ev.isError;
      } else {
        if (typeof prev.result !== 'string') prev.result = JSON.stringify(prev.result);
        prev.result += resultStr;
      }
      prev.ts = ev.ts;
      scheduleUIUpdate(false, true);
      return;
    }
    if (prev.type === 'tool_start' || prev.type === 'run_end' || prev.type === 'run_start') break;
  }
  ev.result = resultStr;
}
```

The key insight: a JSON envelope result (`{content: [...], details: {...}}`) is a **complete value**, not a streaming delta. It replaces intermediate partial text. Raw text results are still appended (preserving streaming exec output).

## Edge Cases

| Sequence | Behavior | Correct? |
|----------|----------|----------|
| plain text → plain text | append | ✓ exec streaming |
| plain text → JSON envelope | replace | ✓ update→done (the fix) |
| JSON envelope → JSON envelope | replace | ✓ result→done, duplicates |
| JSON envelope → plain text | append | ✓ shouldn't happen (order is update→done), but safe |
| 3+ phases (update → result → done) | replace at each JSON step | ✓ final envelope wins |
| single phase (done only) | no merge needed | ✓ fast sync tools |

## Testing / Verification

### Manual test

1. Start deepclaw-ui: `node deepclaw-ui.js`
2. Open dashboard, send a message that triggers an `edit` or `write` tool call
3. Observe tool results during streaming — should show formatted diff/card, not raw JSON
4. Switch sessions in sidebar and back — rendering should be identical
5. Check that `exec` streaming output still accumulates incrementally (via `process poll`)

### Code-level verification

1. `parseToolResult(prev.result)` should return `{isEnvelope: true, details: {...}}` after the fix
2. Before the fix, `parseToolResult(prev.result)` returns `{isEnvelope: false, details: null}` for corrupted events
3. Disk `data/session-*.json` should still store events separately (backend unchanged)

## Related

- `docs/websocket-client.md` — `event.added` handler, streaming merge
- `docs/event-rendering.md` — `renderEditHeader`, `parseToolResult`, per-tool result renderers
- `docs/message-processing.md` — `convertToFrontendEvent`, tool_result creation, `agent` stream handling
- Source: `index.html` ~L1100-1116 (merge), ~L2117 (`parseToolResult`), ~L3808 (`renderToolResult`)
- Source: `deepclaw-ui.js` L442-468 (`agent` stream), L470-510 (`session.tool` stream), L887-898 (`_makeEventKey`)
- Source: `deepclaw-ui.js` L927-933 (`addEvent` broadcast), L1097-1100 (`broadcastToClients`)

## Implementation (2026-06-02)

Three changes applied to `index.html`:

### 1. New helper: `tryParseToolResultEnvelope(str)`
Added after `parseToolResult()` in Section 13. Returns the parsed JSON object if
`str` is a valid tool result envelope (`{content: [...]}`), otherwise `null`.

### 2. Smart merge in `event.added` handler (Option A)
Replaced blind concatenation at the tool_result merge block. When the incoming
result is a JSON envelope, it **replaces** the previous partial result entirely
(final `done` JSON supersedes intermediate `update` text). Plain-text deltas
(e.g., exec stdout chunks) are still appended as before.

### 3. Dedup in raw `session.tool` handler (additional fix)
The raw handler's `phase === 'done'` branch now checks for an existing
tool_result from `event.added` (created during `update` phase) and merges into
it instead of unconditionally pushing a duplicate. This eliminates the cosmetic
double-rendering of tool results during streaming.
