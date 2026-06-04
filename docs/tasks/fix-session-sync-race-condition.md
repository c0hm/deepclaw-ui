# Fix: Session Sync Race Condition on Fresh Load

**Status:** Fixed (2026-06-02 04:40 GMT-3) — Server sends sessionKey + 100-event limit; frontend loads full history on-demand.

**Date:** 2026-06-02

## Original Bug

"When loading miniclaw-ui fresh if it enters the page at the same time it receives streaming events then it wont load correctly, forced f5 until it can load."

## Root Cause Analysis

### Finding #1: `session.sync` is silently dropped

**Server** sends `session.sync` on browser connect (line 1284):

```javascript
ws.send(JSON.stringify({
  type: 'event',
  event: 'session.sync',
  payload: sess.toClientFormat()  // Returns { key: 'agent:main:main', events: [...], ... }
}));
```

**Frontend** extracts session key at line 878:

```javascript
const sk = payload.sessionKey || msg.sessionKey;
```

- `payload.sessionKey` → **undefined** (payload uses `key`, not `sessionKey`)
- `msg.sessionKey` → **undefined** (not a top-level field in the message structure)

Then at line 879:
```javascript
if (!sk) return;  // ← DROPS session.sync entirely!
```

The `session.sync` handler (line 941) is **never reached**. Historical events are never loaded. The frontend relies entirely on `event.added` for event population.

### Finding #2: Why the fix blocks the page

The obvious fix is to also check `payload.key`:
```javascript
const sk = payload.sessionKey || payload.key || msg.sessionKey;
```

This causes `session.sync` to be processed — but for the first time ever in this codebase. The handler does heavy synchronous work:

1. Iterates over 2000 events (`.forEach`)
2. Two `.filter()` passes over 2000 events (user_text pruning)
3. Reverse loop with `Array.splice()` deduplication
4. Then calls `tryAutoSelect()` → `showSession()` → `showSessionContent()` which **synchronously generates DOM HTML for all 2000 events**

The test environment has **5 sessions**, 3 of which have **2000 events each**. The total synchronous processing time for all sync messages + DOM construction freezes the browser for seconds.

Additionally, `showSessionContent()` is called during the sync batch (from `tryAutoSelect`), blocking the main thread and preventing remaining sync messages from being processed at all. The console shows only 2 of 5 sync logs before the freeze.

## Attempted Fixes (All Failed)

### Attempt 1: Defer `tryAutoSelect` with 50ms setTimeout
- `setTimeout(() => tryAutoSelect(), 50)` still fired during the sync batch (5 sessions × ~50ms each = 250ms), causing the same freeze.

### Attempt 2: Guard + 300ms timeout
- `_syncAutoSelectTimer` flag prevents multiple scheduling
- 300ms delay after the **first** sync before auto-selecting
- **Still froze** — the DOM construction for 2000 events is inherently too expensive to run synchronously regardless of delay timing.

## Why Reverted

All approaches that enable `session.sync` processing for large sessions (>1000 events) will freeze the page during DOM construction. The handler was effectively dead code before, and the system worked (mostly) by accident — events arrived via streaming `event.added` only, which accumulates gradually rather than rendering all at once.

## Proposed Solutions

### Option A: Server-side — Don't send full events in `session.sync`

Only send session **metadata** (key, tokens, model, eventCount) in `session.sync`, not the events array. Frontend fetches events on-demand via REST API when a session is selected.

```javascript
// Server: send summary instead of full data
ws.send(JSON.stringify({
  type: 'event',
  event: 'session.sync',
  payload: sess.toClientSummary()  // No events array
}));

// Frontend REST fallback already exists:
fetch(`/api/events/${sk}?limit=200`)
```

**Pros:** Minimal data transfer, fast page load, events loaded on demand
**Cons:** Slight delay when first selecting a session (API round-trip)

### Option B: Server-side — Limit events in sync to last N

Send only the last 200 events in `session.sync`, enough to show recent activity without blocking.

```javascript
ws.send(JSON.stringify({
  type: 'event',
  event: 'session.sync',
  payload: {
    ...sess.toClientFormat(),
    events: sess.events.slice(-200),
    sessionKey: sk,
    truncated: sess.events.length > 200
  }
}));
```

**Pros:** Simple, fast, backward-compatible
**Cons:** Older events not immediately visible; need "load more" mechanism

### Option C: Frontend — Virtual scrolling / lazy render

Make `showSessionContent` only render visible events (intersection observer + virtual scroll). This is a bigger refactor but would solve the root problem for ALL rendering, not just initial load.

**Pros:** Universal fix — all large sessions benefit
**Cons:** Complex, large refactor, many renderers to update

### Option D: Frontend — Render in chunks with `requestIdleCallback`

After `session.sync`, render events in batches of 100 using `requestIdleCallback` or `setTimeout(0)` to avoid blocking the main thread.

**Pros:** Keeps full sync, doesn't block
**Cons:** Events appear gradually (can be confusing UX); complex state management

## Recommendation

**Option A + B hybrid:**
1. Fix `session.sync` to include `sessionKey` (server)
2. Limit events in sync to last 100 (server)
3. Frontend detects `payload.sessionKey` (already works with Option A's server fix)
4. When user selects a session, frontend fetches full history via REST API if `truncated` flag is set

This is the smallest change with the best UX — page loads fast, recent events show immediately, and full history is available on demand.

## Files Affected

- `miniclaw-ui.js` — `wss.on('connection')` handler (line ~1280), `toClientFormat()`, `toClientSummary()`
- `index.html` — `handleGatewayMsg()` (line ~878), `session.sync` handler (line ~941), `showSessionContent()` (line ~1734)

## Test Environment

- 5 sessions: 3 with 2000 events (at limit), 1 with ~500, 1 with ~400
- Total sync payload: ~5-10 MB JSON
- Session `agent:deepui:main` is typically `running` status (active streaming)
