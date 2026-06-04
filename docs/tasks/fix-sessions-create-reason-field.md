# Fix: sessions.create — "Start new session" dialog failing

**Date:** 2026-06-01  
**Status:** Fixed

## Problem

The "Start New Session" modal dialog was showing "⚠️ Failed" for all new session creations. The session would appear in the sidebar with the failed marker after ~10 seconds.

## Root Cause

The OpenClaw Gateway changed the `sessions.changed` event payload from using `state: "created"` to `reason: "create"`. Both the miniclaw-ui backend (`miniclaw-ui.js`) and frontend (`index.html`) were checking for `state === 'created'` (or `phase === 'created'`) but the gateway now sends `reason: "create"`.

The same issue affected session deletion events: the gateway sends `reason: "deleted"` instead of `state: "deleted"/"ended"`.

### Flow that broke

1. User clicks "Start" in the modal → frontend sends `sessions.create` WS req to backend
2. Backend forwards `sessions.create` to gateway
3. Gateway creates session, broadcasts `sessions.changed` with `{ sessionKey, reason: "create" }`
4. Backend's `handleGatewayMessage` receives it but `state === 'created'` check never matches
5. Backend broadcasts raw event to browser clients
6. Frontend's `handleGatewayMsg` receives it but `state === 'created'` check never matches
7. Frontend's `_optimistic` flag is never cleared
8. Polling in `createNewSession()` times out after 10s → sets `_failed = true` → shows "⚠️ Failed"

## Fix

Added `reason` field checks alongside existing `state`/`phase` checks:

### Backend (`miniclaw-ui.js`) — 3 changes

1. **Line ~1619** — Session deletion handler: Added `reason === 'deleted' || reason === 'ended'` check
2. **Line ~1651** — Deleted sessions guard: Added `reason === 'create'` check to allow re-creation
3. **Line ~1774** — Session creation handler: Added `reason === 'create'` check to reset session state

### Frontend (`index.html`) — 4 changes

1. **Line ~852** — Early deletion handler: Added `reason === 'deleted' || reason === 'ended'` check
2. **Line ~875** — Deleted sessions guard: Added `reason === 'create'` check
3. **Line ~1201** — Main creation handler: Added `reason === 'create'` check (clears `_optimistic`)
4. **Line ~1249** — Global stats increment: Added `reason === 'create'` check

## Gateway Event Format

The gateway's `emitSessionsChanged` function (in `sessions-oEeA9KYg.js`) sends:

```json
{
  "type": "event",
  "event": "sessions.changed",
  "payload": {
    "sessionKey": "agent:main:xxx",
    "reason": "create",
    "ts": 1780290972117,
    "sessionId": "...",
    ...
  }
}
```

The `reason` field can be: `"create"`, `"send"`, `"steer"`, `"deleted"`.

There is no `state` or `phase` field in gateway-generated `sessions.changed` events. The backend still generates synthetic events with `state`/`phase` (e.g., for stale session removal after sync).

## Verification

Tested via WebSocket:
```
> sessions.create { key: "agent:main:testfix" }
< res { ok: true, payload: { key: "agent:main:testfix", created: true } }
< sessions.changed { sessionKey: "agent:main:testfix", reason: "create", ... }

Backend log: [info] Creating new session: agent:main:testfix
```

## Additional Fix: Modal button row not restored

After fixing the `reason` field, sessions were created successfully but the
modal stayed stuck showing "Creating session..." spinner on reopen.

**Root cause:** `createNewSession()` replaces the button row's `innerHTML`
with a spinner. `closeNewSessionModal()` only hides the modal and clears
inputs — it never restores the Cancel/Start buttons. Reopening the modal
showed the spinner with no way to interact.

**Fix:** `closeNewSessionModal()` now restores the original button row HTML.
