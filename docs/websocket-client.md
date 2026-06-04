# Browser WebSocket Client

The frontend connects to the miniclaw-ui backend server via WebSocket. This document covers the actual connection lifecycle, all message types sent and received, and the deduplication system — all as implemented in `index.html`.

---

## Connection

```javascript
const proto = location.protocol === 'https:' ? 'wss' : 'ws';
ws = new WebSocket(proto + '://' + location.host);
```

- **Protocol:** Auto-detected from `window.location.protocol` (`ws` for http, `wss` for https)
- **Endpoint:** `ws://<host>` or `wss://<host>` (same host, same port as the HTTP page)
- **Reconnect:** On `ws.onclose`, reconnects after 3 seconds

### Lifecycle Callbacks

| Callback | Behavior |
|----------|----------|
| `ws.onopen` | Sets status to "Connected", clears deletion tracking, resets auto-select. If no sessions appear in 2 seconds, falls back to `GET /api/sessions` to populate the session list. |
| `ws.onclose` | Sets status to "Disconnected", schedules reconnect in 3 seconds |
| `ws.onerror` | Sets status to "Connection error" |
| `ws.onmessage` | Parses JSON, then dispatches: `connected` → ignored, `reset` → clears ALL sessions and stats, everything else → `handleGatewayMsg(msg)` |

---

## Messages Sent (Frontend → Server)

| Type | Payload | Trigger |
|------|---------|---------|
| `chat` | `{ type:'chat', message, sessionKey }` | User sends a message via chat input |
| `req` (abort) | `{ type:'req', method:'sessions.abort', params:{ key } }` | User clicks Stop button or sends test traffic |
| `req` (create) | `{ type:'req', method:'sessions.create', params:{ key } }` | User creates a new session via modal |
| `ping` | `{ type:'ping' }` | _(available but not actively sent from frontend code)_ |

The `chat` message payload also supports `{ type:'test', message }` for the test traffic button.

---

## Messages Received (Server → Frontend)

All messages are handled by `handleGatewayMsg()` in `index.html`. The handler dispatches on `msg.event || msg.name` for gateway-style messages, or `msg.type` for server-originated messages.

### Session Lifecycle

| Event | Payload | Behavior |
|-------|---------|----------|
| `session.summary` | `{ sessionKey, sessionId, tokens:{...}, lastTs }` | Lightweight metadata sent on WebSocket connect for each existing session. Sets `sessionId`, all token fields (`inputTokens`, `outputTokens`, `totalTokens`, `contextTokens`, `estimatedCostUsd`, `model`, `modelProvider`), and `lastTs`. Triggers `tryAutoSelect()`. **These are NOT events — they update session metadata only.** |
| `session.sync` | `{ key, sessionId, events[], messages[], tokens{} }` | Full session data sent on connect. **Replaces** the events array (not appends). Prunes: stale `user_text` events (non-canonical/non-local sources), corrupted events with render artifacts, duplicate canonical user_text events within 2s windows. Updates tokens, model, and triggers auto-select. |
| `session.synced` | `{ sessionKey }` | Marker indicating history fetch has completed for this session. Handled as a no-op in the frontend (no specific handler exists, but this event type may arrive). |
| `session.cleared` | `{ sessionKey }` | Events array has been cleared server-side. Resets rendered cache, re-fetches session data from `GET /api/session/<key>`, then updates events/messages/tokens from the API response. |
| `session.deleted` | _(handled via `sessions.changed` with state `'ended'` or `'deleted'`)_ | See `sessions.changed` below. |
| `session.dirty` | `{ sessionKey }` | Session state is stale on the server. The frontend should request a full `session.cleared` + sync cycle. _(No specific handler exists in current code, but this is the canonical signaling protocol.)_ |
| `session.ack` | `{ sessionKey }` | Acknowledgment that a chat message was received by the session layer. Triggers UI refresh only. |
| `session.tokens.deleted` | `{ sessionKey }` | Removes token data from `globalStats`. |

### Real-Time Events

| Event | Payload | Behavior |
|-------|---------|----------|
| `event.added` | Full event object | **The primary real-time event ingestion pipeline.** Appends one event to the session's `events` array. Handles: streaming merge (assistant_text, thinking, tool_result), deduplication (tool_start, run_start, run_end, run_error by runId/toolCallId), pending message upgrade, loading placeholder removal, user_text dedup, and stats tracking. The most complex handler in the frontend. |
| `session.tool` | `{ sessionKey, runId, stream, data }` | **Legacy gateway event handler.** Dispatches by `stream` value: `tool` (tool_start/tool_result/update phases), `lifecycle` (run_start/run_end/run_error phases), `thinking` (streaming merge), `assistant` (streaming merge), `user` (gateway echo — never pushes, event.added is the sole authority), `error` (run_error). |
| `session.message` | `{ sessionKey, message:{ role, content[] }, session:{ tokens... } }` | Legacy message handler. Extracts token data from `payload.session`, merges model/provider metadata, clears pending state when `role === 'assistant'`. **Does NOT push `user_text`/`assistant_text` events.** |

### Session State Changes

| Event | Payload | Behavior |
|-------|---------|----------|
| `sessions.changed` | `{ sessionKey, state, phase, session:{}, tokens:{} }` | Multi-state handler. Dispatches on `state`: `'ended'`/`'deleted'` → removes session from Map, updates sidebar, selects next session. `'created'` → initializes empty session (clears events, tokens, messages; upgrades optimistic → real). `'active'` → increments global session counter. Additionally on `phase === 'loaded'` → sets full session data (tokens, model, status), increments global session count. |
| `session.messages` | `{ sessionKey, messages[] }` | Processes content blocks for dedup hashing via `isSeenMessage()`. Does not push events. |
| `sessions.history` | `{ sessionKey, messages[] }` | Appends historical messages as `user_text`/`assistant_text` events to the session. |
| `agent` | `{ sessionKey }` | Increments `globalStats.llmCalls` and ensures session exists via `getSession()`. |
| `chat` | `{ sessionKey, stopReason }` | Creates a `run_end` event with the given stopReason. |

### Acknowledgments & Heartbeats

| Event | Payload | Behavior |
|-------|---------|----------|
| `chat_ack` | `{ sessionKey }` | Backend confirmed message was forwarded to gateway. Triggers UI refresh only; does NOT upgrade pending messages. |
| `chat_delivered` | `{ sessionKey }` | Gateway confirmed message was delivered to session. Triggers UI refresh only; does NOT upgrade pending messages. Only `event.added` handles pending→delivered transitions. |
| `heartbeat` | `{}` | Acknowledged silently (no-op). |

### Session Token Updates

| Event | Payload | Behavior |
|-------|---------|----------|
| `session.tokens` | `{ sessionKey, tokens:{...} }` | Updates session token fields. Special logic: when gateway-reported `contextTokens >= 200000`, calculates actual context via `calculateActualContext()` from stored events (tool input/result text ÷ 4, assistant text ÷ 4). |
| `session.tool` (token phase) | `{ sessionKey, tokens:{...} }` | _(Handled as part of the `session.tool` handler above.)_ |

### Reset

| Event | Behavior |
|-------|----------|
| `reset` | Handled in `ws.onmessage` BEFORE `handleGatewayMsg`. Clears ALL sessions (Map.clear, events emptied), resets `globalStats` to zero, re-renders UI. |

---

## Deduplication System

### Message-Level Dedup (`isSeenMessage`)

Used by `session.messages` handler to avoid re-processing identical content blocks.

- **Signature:** `role + '|' + hashStringForMsg(content.trim())`
- **Hash:** `hashStringForMsg()` is a string hash (djb2 variant), NOT a truncated first-100-chars comparison
- **Scope:** Per-session, stored in `sess._seenMsgHashes` (a `Set`)
- **Max entries:** 1,000 (when exceeded, keeps the most recent 500)
- **No timestamp component** in the signature

### Text Event Dedup (`hasExistingTextEvent`)

Used by `session.tool` handler's `text` stream (legacy assistant text path) to avoid pushing duplicates.

- **Signature:** Matches by `runId` + `type` + text equality/substring overlap
- **Behavior:** Returns `true` if any event with same `runId` and `type` has text that is a superset (or subset) of the given text
- **Purpose:** Prevents double-emission of assistant_text from the legacy gateway code path

### `event.added` Dedup

The `event.added` handler has its own inline deduplication:
- **Streaming merge:** `assistant_text`, `thinking`, and `tool_result` events with same `runId`/`toolCallId` are merged into a single event (text appended) rather than creating duplicates
- **Exact duplicate prevention:** `tool_start` (by `toolCallId`+`runId`), `run_start` (by `runId`), `run_end` (by `runId`), and `run_error` (by `runId`) are checked for existing entries and silently dropped if found
- **User text dedup:** Incoming `user_text` from server is dropped if a local pending copy (same text) was already injected. Otherwise, checked for exact text match against all existing `user_text` events.

### Session Sync Dedup

The `session.sync` handler performs additional dedup during full session load:
- **Stale user_text pruning:** Drops events with non-canonical/non-local `source` values
- **Corruption detection:** Drops `user_text` events whose text contains render artifacts (`👤 USER`, `msg-header`, `msg-role`)
- **Canonical user_text dedup:** Multiple canonical events with identical text (first 80 chars) within the same 2-second window are collapsed to one

---

## Chat Input Flow (Pending/Optimistic System)

The frontend implements a full optimistic chat flow:

1. **Pre-send guard:** `_pendingRequest` flag prevents double-sending
2. **Optimistic injection:** A `user_text` event with `pending: true` and `source: 'local'` is injected immediately into the session
3. **Ghost cleanup:** Any stale canonical `user_text` events with the same text (from page-refresh disk load) are removed before injection
4. **Loading placeholder:** After 800ms, a `loading` event is injected to show a waiting indicator
5. **Button states:** Send → "Sending..." (800ms) → "⏹ Stop" (red, clickable to abort)
6. **Timeout:** After 60 seconds with no response activity, a `run_error` event is injected and pending state is cleared
7. **Delivery confirmation:** When a response event arrives (`run_start`, `thinking`, `tool_start`, `assistant_text`, `run_error`), loading placeholders are removed and pending messages are upgraded to `delivered: true`
8. **Pending state cleanup:** Triggered by `run_end`, `run_error`, `session.message` (assistant), or `sessions.changed (ended/deleted)`

### Pending State Global Variables

| Variable | Purpose |
|----------|---------|
| `_pendingRequest` | True while a request is in flight (between Send and response end) |
| `_pendingSentMsg` | Text of the last sent message (for optimistic matching) |
| `_lastSentSessionKey` | Session key where the last message was sent |
| `_lastActivityTs` | Timestamp of last response event (for 60s timeout awareness) |

---

## Related

- [index.md](index.md) — Overview
- [event-types-reference.md](event-types-reference.md) — Event type details
- [ui-components.md](ui-components.md) — UI state management
