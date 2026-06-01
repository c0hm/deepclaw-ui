# Dynamic Agent List in New Session Modal

**Date:** 2026-06-01  
**Status:** Done

## Problem

"Your AI Gateway" sidebar (the one Ju is using) has two named agents here:
  - main agent `deepui`
  - next-gen-js

The "Start New Session" modal's agent `<select>` is **hardcoded** with only two options — and it's wrong for this gateway:

```html
<select id="new-session-agent">
  <option value="agent:main:main">main</option>
  <option value="agent:personal:main">personal</option>
</select>
```

- `agent:personal:main` may not even exist on Ju's gateway
- The actual agents (`deepui`, `next-gen-js`) are missing entirely
- If the gateway config changes (agents added/removed), the modal stays stale

## Resolution

### Findings from `openclaw.json` inspection

The config file has 3 agents in `agents.list`:
- `id: "main"` — `model: "deepseek/deepseek-v4-pro"`, empty `skills: []`, has `tools.profile: "coding"` and `heartbeat: { every: "0m" }` (disabled)
- `id: "deepui"` — `model: "deepseek/deepseek-v4-pro"`, empty `skills: []`
- `id: "personal"` — `model: "deepseek/deepseek-v4-pro"`, non-empty `skills` with understand-* entries

No explicit `kind`/`type` field distinguishes chat from tool-only agents. All three agents have a `model` field. Filtering by presence of `.model` was chosen as the conservative approach (tool-only agents wouldn't have a model).

**Session key format:** `agent:<agent-id>:main` — confirmed from the hardcoded options (`agent:main:main`, `agent:personal:main`) and the `createNewSession()` code that extracts base from `agent.split(':')[0] + ':' + agent.split(':')[1]`.

### Backend changes (`deepclaw-ui.js`)

**`/api/agents` endpoint** (lines 843–863):
- Added `.filter(a => a.model)` to exclude tool-only entries
- Added `sessionKey` field: `agent:${a.id}:main`
- Response shape: `{ agents: [{ id, model, sessionKey }] }`

### Frontend changes (`index.html`)

**New global** (line 496):
```js
let _agentList = []; // cached agent list from /api/agents
```

**`fetchAgentList()`** (line 3179): Fetches `/api/agents` and caches to `_agentList`. Called from `ws.onopen`.

**`populateAgentSelect(agents)`** (line 3191): Replaces `<select>` options with dynamic list. Uses provided agents or cached `_agentList`. Displays `id (model)` as label. Falls back to hardcoded `agent:main:main` if list is empty.

**`showNewSessionModal()`** (line 3223): Now checks cache first; if empty, fetches from API and populates on response.

**`sendNewSession()` fallback** (line 3070):
```js
const sk = activeSession || (_agentList.length > 0 ? _agentList[0].sessionKey : 'agent:main:main');
```

**`sendChatMessage()` fallback** (line 3438): Same dynamic fallback.

**`ws.onopen`** (line 701): Calls `fetchAgentList()` after connection setup.

## Files Changed

| File | Change |
|------|--------|
| `deepclaw-ui.js` L843–863 | `/api/agents`: filter by `.model`, add `sessionKey` field |
| `index.html` L496 | Add `_agentList` global |
| `index.html` L701 | `ws.onopen`: call `fetchAgentList()` |
| `index.html` L3070 | `sendNewSession()`: dynamic fallback session key |
| `index.html` L3179–3264 | New `fetchAgentList()`, `populateAgentSelect()`, updated `showNewSessionModal()` |
| `index.html` L3438 | `sendChatMessage()`: dynamic fallback session key |
