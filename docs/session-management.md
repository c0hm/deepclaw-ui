# Session Management

## SessionState

```javascript
class SessionState {
  key;              // e.g. "agent:main:main"
  sessionId = '';   // Gateway-assigned ID
  events = [];      // Frontend events (max 2000)
  messages = [];    // User/assistant messages (max 500)
  _seenEventKeys = new Set(); // Event-level dedup keys (max 2000→1000)
  tokens = {
    inputTokens: 0,
    outputTokens: 0,
    totalTokens: 0,
    totalTokensFresh: false,   // Set by gateway on fresh token count
    contextTokens: 0,
    estimatedCostUsd: 0,
    model: '',
    modelProvider: '',          // Provider identifier from gateway
    status: ''                  // Session status
  };
  lastTs = new Date();
  createdAt;        // null if loaded from disk (set on construction otherwise)
  _lastMsgBroadcastCount = 0;  // Tracks how many messages have been broadcast
}
```

**Limits:** max 2000 events, max 500 messages per session (oldest dropped).

## Storage

```javascript
sessions = new Map();           // sk → SessionState
saveTimers = new Map();         // sk → setTimeout (debounced saves)
deletedSessions = new Set();    // Keys explicitly deleted — blocks re-creation from in-flight events
DATA_DIR = path.join(__dirname, 'data');  // ./data
SAVE_DEBOUNCE_MS = 1000;       // 1 second debounce window
```

## Key Operations

### getSession(sk, loadFromDisk = true)

Creates or retrieves a SessionState. **Loads from disk by default** (`loadFromDisk` defaults to `true`). If the session doesn't exist in memory, creates a new `SessionState(sk, true)` which calls `load()` in the constructor.

```javascript
function getSession(sk, loadFromDisk = true) {
  if (!sessions.has(sk)) {
    sessions.set(sk, new SessionState(sk, loadFromDisk));
  }
  return sessions.get(sk);
}
```

### addEvent(ev)

Adds a frontend event to the session:
1. Sets `ev.ts = new Date()` and auto-generates `ev.id` if missing
2. Builds dedup key via `_makeEventKey(ev)` and skips if already seen
3. Adds to `_seenEventKeys` Set (bounded: 2000 entries, trim to 1000 most recent)
4. Pushes event, updates `lastTs`
5. Trims to 2000 events (keeps newest)
6. Calls `save()` (debounced)
7. Broadcasts `event.added` to all browser clients in real-time

### addMessage(msg)

Adds a message to the session:
1. Auto-generates `ts` (ms epoch) and `id` if missing
2. Pushes to `messages` array
3. Trims to 500 messages (keeps newest)
4. Updates `lastTs`
5. Calls `save()` (debounced)

### updateTokens(tokens, broadcast = true)

Merges token fields into `this.tokens`, calls `save()`, and optionally broadcasts to clients via `session.tokens` event.

### save()

**Debounced** disk persist. Calls `scheduleSave(this.key, this)` which batches writes within a 1-second window. Multiple rapid `save()` calls collapse into a single `_doSave()`.

### _doSave()

**Immediate** atomic disk write. Used for:
- After the debounce timer fires (from `scheduleSave`)
- Critical operations (reset, delete, shutdown)
- On `clear-events`

Atomic write process:
1. Writes JSON to `data/session-{key}.json.tmp`
2. Renames `.tmp` → `.json` (atomic on Linux/macOS)

**Disk format:**
```json
{
  "key": "agent:main:main",
  "sessionId": "...",
  "events": [...],
  "messages": [...],
  "tokens": {...},
  "createdAt": "2024-01-01T00:00:00.000Z",
  "lastTs": "2024-01-01T00:00:00.000Z"
}
```

> ⚠ `key` and `lastTs` are written to disk but **never read back** by `load()`. `key` is a constructor arg, `lastTs` is rebuilt during event replay.

### load()

Reads `data/session-{key}.json` and restores:
- `sessionId`, `events`, `messages`, `tokens`, `createdAt`
- Rebuilds `_seenEventKeys` Set from loaded events
- Sets `_lastMsgBroadcastCount` to current message count (prevents re-broadcasting historical messages)
- Does **NOT** restore `messageSignatures` from disk — persisted hashes cause false duplicates across server restarts

### toClientFormat()

Returns full session for API/WS sync:
```javascript
{ key, sessionId, events, messages, tokens, createdAt, lastTs }
```

### toClientSummary()

Returns lightweight summary (no events/messages arrays):
```javascript
{ key, sessionId, eventCount, messageCount, tokens, createdAt, lastTs }
```

> ⚠ `toClientSummary()` is defined but appears **unused** in current code. The `/api/sessions` endpoint builds its summary inline, and WS sync uses `toClientFormat()`.

## Debounced Save System

```javascript
const saveTimers = new Map();       // sk → setTimeout
const SAVE_DEBOUNCE_MS = 1000;     // 1 second window

function scheduleSave(sk, session) {
  if (saveTimers.has(sk)) {
    clearTimeout(saveTimers.get(sk));  // Reset timer on new save
  }
  saveTimers.set(sk, setTimeout(() => {
    saveTimers.delete(sk);
    session._doSave();                 // Actually write to disk
  }, SAVE_DEBOUNCE_MS));
}
```

Every `save()` call resets the 1-second timer for that session. Multiple events within 1 second produce a single disk write.

### Graceful Shutdown

```javascript
function flushAllSaves() {
  saveTimers.forEach((timer, sk) => {
    clearTimeout(timer);
    const sess = sessions.get(sk);
    if (sess) {
      try { sess._doSave(); } catch (e) { /* ignore */ }
    }
  });
  saveTimers.clear();
}
process.on('SIGINT', () => { flushAllSaves(); process.exit(0); });
process.on('SIGTERM', () => { flushAllSaves(); process.exit(0); });
```

On SIGINT/SIGTERM: clears all pending debounced timers and immediately flushes every session to disk before exiting.

## Session Lifecycle

### Created

When `sessions.changed` event arrives with `state === 'created'` or `phase === 'created'`:
- Clears `deletedSessions` marker for this key
- Resets events/messages/tokens to empty
- Calls `_doSave()` (immediate persist of cleared state)
- Deletes old disk file if it exists

### Deleted (by user)

1. Browser calls `/api/session/:key/delete` or WS `sessions.delete`
2. Sends `sessions.delete` to gateway
3. Cancels any pending debounced save
4. Removes from `sessions` Map
5. Adds key to `deletedSessions` Set
6. Deletes disk file

### Deleted (by gateway)

When gateway syncs and a session is no longer present, or `sessions.changed` with `state === 'ended'` or `'deleted'`:
- Adds key to `deletedSessions`
- Removes from memory
- Deletes disk file
- Broadcasts deletion to all browser clients

### DeletedSessions Guard

```javascript
const deletedSessions = new Set();  // Blocks re-creation from in-flight events
```

When a user deletes a session but in-flight gateway events still reference it, `deletedSessions` prevents `getSession(sk)` from re-creating it. The guard is:
- **Set** on explicit delete (user API/WS call) and gateway-ended events
- **Cleared** on fresh gateway connection (`connect` success)
- **Cleared for individual keys** only when `sessions.changed` with `state === 'created'` arrives (genuine re-creation)

## Event Deduplication

```javascript
// In SessionState:
_seenEventKeys = new Set();

_makeEventKey(ev) {
  const parts = [ev.type || '', ev.runId || ''];
  if (ev.text) parts.push(hashString(ev.text));
  if (ev.toolName) parts.push(ev.toolName);
  if (ev.toolCallId) parts.push(ev.toolCallId);
  if (ev.input) parts.push(hashString(
    typeof ev.input === 'string' ? ev.input : JSON.stringify(ev.input)
  ));
  return parts.join('|');
}
// Bounded: 2000 entries, trims to 1000 most recent
```

## Message Deduplication

```javascript
messageSignatures = new Map();  // global: sk → Set of signatures

// Signature: role + '|' + hashString(content.trim())
// hashString = 32-bit rolling hash → base36
// Window: 500 entries per session, trims to 250 oldest when exceeded
```

## Chat Request Routing

```javascript
chatRequests = new Map();  // id → { ws, sessionKey }
```

Per-request tracking to route gateway responses back to the originating browser client. Keyed by request ID (not session key) to avoid races between multiple browser clients. Entries cleaned up on client disconnect.

## Context Token Calculation

```javascript
function calculateActualContext(events) {
  let totalChars = 0;
  events.forEach(ev => {
    if (ev.input && typeof ev.input === 'string') totalChars += ev.input.length;
    if (ev.result && typeof ev.result === 'string') totalChars += ev.result.length;
    if (ev.text && typeof ev.text === 'string') totalChars += ev.text.length;
    if (ev.thinking && typeof ev.thinking === 'string') totalChars += ev.thinking.length;
  });
  return Math.ceil(totalChars / 4);
}
```

Used during `sessions.list` response to compute context tokens from local events. Overrides gateway value when local calculation produces a non-zero result.

## isFinal / isIntermediate Markers

When `run_end` arrives for a runId in `handleGatewayMessage`:
- Last `assistant_text` for that runId → `isFinal: true`, `isIntermediate: false`
- Earlier `assistant_text` for the same runId → `isIntermediate: true`

These markers power the `/api/session/:key/clear-events` filtering.

## clear-events Endpoint

`POST /api/session/:key/clear-events`:
1. Cancels pending debounced save
2. Filters events: keeps `user_text` + only `isFinal` assistant_text
3. Falls back to `source !== 'message'` + `hasToolCalls` heuristic for historical data
4. If nothing would be removed (already clean), clears everything
5. Rebuilds `_seenEventKeys` from remaining events
6. Resets tokens
7. Calls `_doSave()` (immediate persist)
8. Broadcasts `session.cleared` event

## Browser Client Sync

On WebSocket connect, each browser client receives:
1. `status` event: `{ gatewayReady, sessionCount, clientCount, ts }`
2. `session.sync` event for **every** active session (full `toClientFormat()`)

New events are pushed in real-time via `event.added` broadcast.

## Limits Summary

| Limit | Value |
|-------|-------|
| Events/session | 2000 |
| Messages/session | 500 |
| Event dedup keys/session | 2000 (trim to 1000) |
| Message dedup signatures/session | 500 (trim to 250) |
| Save debounce | 1000ms |

## Related

- [index.md](index.md) — Overview
- [gateway-websocket.md](gateway-websocket.md) — Gateway events
- [message-processing.md](message-processing.md) — Event conversion
- [http-api.md](http-api.md) — REST API endpoints
