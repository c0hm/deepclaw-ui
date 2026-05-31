# Message Processing

## convertToFrontendEvent(rawMsg) → event|event[]|null

Transforms raw Gateway events into frontend event objects.

### session.tool → Frontend events

| Stream | Phase | Frontend Type | Notes |
|--------|-------|---------------|-------|
| `tool` | `start` | `tool_start` | `{ toolName, input, toolCallId, runId, ts }` |
| `tool` | `done/result/update` | `tool_result` | Only if result/phase=done present; `{ result, isError, toolCallId }` |
| `lifecycle` | `start` | `run_start` | `{ model, ts }` |
| `lifecycle` | `end` | `run_end` | `{ stopReason, ts }` |
| `lifecycle` | `error` | `run_error` | `{ error, ts }` |
| `thinking` | — | `thinking` | `{ text, ts }` — only if text non-empty |
| `assistant` | — | `assistant_text` | `{ text, source: 'stream', ts }` |
| `user` | — | **null** | Gateway echo — **never persisted**. Canonical user_text stored from browser chat. |

### session.message → Frontend events

**Assistant** → returns `[run_start, thinking?, assistant_text, run_end]`

- `run_start` includes full token metadata: `model`, `inputTokens`, `outputTokens`, `totalTokens`, `contextTokens`, `estimatedCostUsd`
- `thinking` event emitted separately if model produced reasoning content (matches streaming behavior)
- `assistant_text`:
  - `source: 'message'` — indicates final assembled message (not streaming delta)
  - Tool calls detected: each `toolCall` content block renders as `[tool: ${block.name}]`
  - `hasToolCalls: true` if any toolCall blocks found
  - `isIntermediate: true` if `hasToolCalls` is set (marks as non-final during tool-call runs)
- `run_end` bookends the run with token metadata: `stopReason: 'end_turn'`, `inputTokens`, `outputTokens`, `totalTokens`, `contextTokens`, `estimatedCost`
  - During `run_end` processing: last assistant_text for the run gets `isFinal: true`, earlier ones get `isIntermediate: true`

**User** → **null** (always)

User text from `session.message` events is **never stored** — the canonical user text is created by the browser chat handler, not from gateway echoes. The gateway echo is explicitly silenced:

```javascript
// session.message user role always returns null
if (role === 'user' && textContent) {
  // Skip system-internal metadata messages
  if (textContent.startsWith('Sender') || textContent.startsWith('System')) {
    return null;
  }
  // Gateway echo — never persist
  return null;
}
```

### sessions.tokens → `tokens_update`

```javascript
{ type: 'tokens_update', inputTokens, outputTokens, totalTokens,
  contextTokens, estimatedCostUsd, model, ts }
```

### agent events (OpenClaw v2026.5.28+) → Frontend events

The gateway registers deepclaw-ui as a `toolEventRecipient` when forwarding
browser chat messages via `sessions.send`. This causes deepclaw-ui to receive
tool events through the `agent` event (targeted to `runToolRecipients`) instead
of `session.tool` (which excludes `runToolRecipients` from the broadcast).

| Stream | Phase | Frontend Type | Notes |
|--------|-------|---------------|-------|
| `tool` | `start` | `tool_start` | Same extraction logic as `session.tool` |
| `tool` | `done/result/update` | `tool_result` | Same extraction logic as `session.tool` |

Non-tool agent streams (lifecycle, thinking, assistant) are intentionally
NOT converted here — they arrive through other gateway paths (`session.tool`,
`session.message`, `sessions.changed`) to avoid duplicates.

### Unknown events → `null` (dropped)

## parseMessageContent(content) → string

Extracts only `type: "text"` blocks from content arrays, ignores everything else:

```javascript
// Input: [{type:'text',text:'hi'},{type:'thinking',thinking:'...'}]
// Output: 'hi'
// Handles: string JSON arrays, raw strings, actual arrays
```

## Deduplication

### Message Deduplication (global, per-session)

```javascript
messageSignatures = new Map();  // sk → Set of signatures

hashString(str) {
  // 32-bit DJB2-style rolling hash → base36
  let hash = 0;
  for (let i = 0; i < str.length; i++) {
    hash = ((hash << 5) - hash) + str.charCodeAt(i);
    hash |= 0;  // clamp to 32-bit
  }
  return hash.toString(36);
}

getMessageSignature(msg) {
  const role = msg.role || 'user';
  const content = (msg.content || '').trim();
  if (!content) return null;  // empty content — never dedup
  // FULL content hash (not truncated). No timestamp component.
  // Two messages with identical role+content are always duplicates
  // regardless of when they were received.
  return role + '|' + hashString(content);
}

isDuplicateMessage(sk, msg) {
  // Returns true if signature already seen
  // Window: 500 entries, trims to 250 oldest when exceeded
}
```

**Key differences from previous doc:**
- Uses **full content hash** (not `slice(0,100)`)
- **No timestamp** in signature
- Window: **500 entries** (not 100), trim to **250** (not full eviction)
- Returns `null` for empty content (bypasses dedup)

### Event Deduplication (per-session, in SessionState)

```javascript
// In SessionState:
_seenEventKeys = new Set();  // event dedup keys

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

addEvent(ev) {
  const key = this._makeEventKey(ev);
  if (this._seenEventKeys.has(key)) return;  // skip duplicate
  this._seenEventKeys.add(key);
  // Bound: 2000 entries, trim to 1000 most recent
}
```

## Metadata Garbage Filter

Applied in `handleGatewayMessage()`, before storing messages:

```javascript
// Regex: /^(Sender|System|\[Mon|\[Tue|\[Wed)/
// NOTE: No ^\[ catch-all — real messages can start with brackets.
// Only matches day-of-week timestamps like "[Mon ...]" or
// internal metadata prefixes "Sender" and "System".
const isMetadataGarbage = /^(Sender|System|\[Mon|\[Tue|\[Wed)/.test(content);
```

## Context Token Calculation

```javascript
function calculateActualContext(events) {
  // Sum text lengths from local events (input, result, text, thinking fields)
  // Divide by 4 (rough char→token estimate)
  // Overrides gateway contextTokens when local data is more accurate
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

## isFinal / isIntermediate Markers

When `run_end` arrives for a runId:
- The **last** `assistant_text` event matching that runId gets `isFinal: true`, `isIntermediate: false`
- **All earlier** `assistant_text` events for the same runId get `isIntermediate: true`
- These markers are used by `/api/session/:key/clear-events` to keep only final responses

## Related

- [index.md](index.md) — Overview
- [gateway-websocket.md](gateway-websocket.md) — Gateway event types
- [event-rendering.md](event-rendering.md) — Display rendering
- [session-management.md](session-management.md) — SessionState internals
