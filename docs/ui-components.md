# UI Components & Layout Reference

> **Complete reference for the DeepClaw UI DOM structure, global state, and interactive components**

---

## DOM Layout

```
<body>
  #header
    #sidebar-toggle (‹/› button)
    h1 "DeepClaw UI"
    #status
      .dot (connected|disconnected)
      #conn-status (text)

  #main
    #sidebar-backdrop (mobile only)
    #sidebar
      #sidebar-header
        "Sessions"
        #session-count (badge)
        + (new session button)
        #delete-session-btn (🗑, shown when activeSession is set)
      #session-list
        .session-item (per session, with .active/.optimistic/.failed modifiers)
          .sk → .sk-text + .delete-btn
          .meta → LLM count + tool count + token sum + error count + .time

    #content
      #content-header
        #content-title (session key + total tokens badge + model badge)
        button bar: filter-toggle, new-session, stop, clear-session

      #filters (hidden by default, toggled via #filter-toggle)
        #filter-text (text input for name/text search)
        .filter-btn[data-filter] × 5: Minimal, All, LLM, Tools, Errors
        #expand-btn + #expand-menu (expand/collapse dropdown)

      #stats-line
        .stat × 4: Sessions, LLM Calls, Tool Calls, Errors

      #messages (scrollable event list)
        .no-session placeholder
        .msg cards, .compact-row, .tc-wrap, .tr-wrap, .session-divider

      #new-msg-btn ("↓ New messages" floating button)

      #resize-handle (drag to resize chat input)

      #chat-input-container
        #chat-input (textarea)
        #history-btn (📜)
        #send-btn

      #input-status (thin bar below chat, shows "Agent is thinking...")

  MODALS (appended to body, outside #main)
    #new-session-modal (create session form)
    #json-viewer-modal (event JSON viewer)
    #history-modal (input history)
```

---

## Global State Variables

All are `let` variables in the top-level script scope (Section 1, lines ~335–350):

| Variable | Type | Default | Purpose |
|---|---|---|---|
| `sessions` | `Map<string, Session>` | `new Map()` | All session data, keyed by session key |
| `deletedSessions` | `Set<string>` | `new Set()` | Keys explicitly deleted; blocks re-creation |
| `activeSession` | `string \| null` | `null` | Currently viewed session key |
| `filter` | `string` | `'all'` | Active filter: `'all'`, `'llm'`, `'tool'`, `'error'` |
| `filterText` | `string` | `''` | Text search filter string |
| `globalStats` | `object` | `{ sessions:0, llmCalls:0, toolCalls:0, errors:0 }` | Aggregate statistics across all sessions |
| `userScrolledUp` | `boolean` | `false` | Whether user has scrolled away from bottom |
| `pendingNewMessages` | `number` | `0` | New message count while scrolled up |
| `sessionEvents` | `Array<Event>` | `[]` | Current session's events with `cumTotal` added |
| `filtersVisible` | `boolean` | `false` | Filters bar visibility (persisted via localStorage) |
| `_expandedItems` | `Set<string>` | `new Set(['user','response'])` | Items to always render expanded (persisted) |
| `_pendingRequest` | `boolean` | `false` | True between message send and response end |
| `_pendingSentMsg` | `string \| null` | `null` | Text of last sent message for optimistic matching |
| `_lastSentSessionKey` | `string \| null` | `null` | Session where last message was sent |
| `_lastActivityTs` | `number` | `0` | Timestamp of last response event, for timeout awareness |
| `sidebarCollapsed` | `boolean` | `false` | Sidebar collapsed state (persisted) |
| `_updateScheduled` | `boolean` | `false` | rAF throttle flag |
| `_updateForceList` | `boolean` | `false` | Force list refresh on next updateUI |
| `_updateForceContent` | `boolean` | `false` | Force content refresh on next updateUI |
| `_lastSessionCount` | `number` | `-1` | Last rendered session count for change detection |
| `_lastEventCount` | `number` | `-1` | Last rendered event count for incremental rendering |
| `_lastFilterHash` | `string` | `''` | Last filter hash for filter change detection |
| `_filteredCache` | `Array` | `[]` | Cached filtered events |
| `_filteredCacheHash` | `string` | `''` | Hash of the cached filter results |
| `_autoSelectAttempted` | `boolean` | `false` | Whether auto-select of last session was attempted |
| `_lastActiveSession` | `string \| null` | from localStorage | Last viewed session key for auto-select |
| `_programmaticScroll` | `boolean` | `false` | Prevents scroll handler during programmatic scroll |
| `_scrollRafId` | `number \| null` | `null` | rAF id for debounced scroll-to-bottom |
| `jsonViewerEvent` | `object \| null` | `null` | Event currently shown in JSON viewer |
| `testBtnDisabled` | `boolean` | `false` | Prevents double-click on test button |

### Per-Session State (inside `sessions` Map values)

| Field | Type | Purpose |
|---|---|---|
| `key` | `string` | Session key (e.g. `agent:main:main`) |
| `events` | `Array<Event>` | All events for this session |
| `messages` | `Array` | Raw gateway messages |
| `lastTs` | `Date` | Last activity timestamp (for sorting) |
| `sessionId` | `string` | Gateway session ID |
| `_seenMsgHashes` | `Set<string>` | Deduplication hash set |
| `_renderedCount` | `number` | How many events rendered (for incremental updates) |
| `_visibleBoundaries` | `number` | How many session boundaries to show (lazy load) |
| `_optimistic` | `boolean` | Session being created (modal spinner) |
| `_failed` | `boolean` | Session creation failed |
| `draft` | `string` | Unsent chat input (preserved on session switch) |
| `inputTokens` | `number` | Total input tokens |
| `outputTokens` | `number` | Total output tokens |
| `totalTokens` | `number` | Total tokens |
| `contextTokens` | `number` | Context window size |
| `estimatedCostUsd` | `number` | Estimated cost in USD |
| `model` | `string` | Model name |
| `modelProvider` | `string` | Model provider |
| `status` | `string` | Session status |
| `tokens` | `object` | Raw tokens object from API fetch |

---

## Filters

### Filter Types
| Filter | Button Label | `getFilteredEvents()` Logic |
|---|---|---|
| `minimal` | Minimal | `e.type === 'user_text' \|\| e.type === 'assistant_text' \|\| e.type === 'thinking' \|\| e.type === 'tool_result'` |
| `all` | All | All events (except `run_end`) |
| `llm` | LLM | `e.type === 'thinking' \|\| e.type === 'assistant_text' \|\| e.type === 'user_text'` |
| `tool` | Tools | `e.type === 'tool_start' \|\| e.type === 'tool_result' \|\| e.type === 'user_text'` |
| `error` | Errors | `e.type === 'run_error' \|\| e.type === 'user_text'` |


### Default & Persistence
- Default filter: `minimal` (on first launch when no saved preference)
- User's last selected filter is persisted to `localStorage` (`deepclaw-ui-prefs.filter`) and restored on reload.

### Always Hidden
`run_end` events are **always filtered** out:

```js
events = events.filter(e => e.type !== 'run_end');
```

### Text Search
The `#filter-text` input searches across:
- `ev.toolName`
- `ev.text`
- `ev.model`
- `ev.error`

### Session Boundary Preservation
Session boundary markers (`run_start` events with `model === 'gateway-injected'`) are **always included** regardless of active filter. They're injected into filtered results and re-sorted by original index position.

### Filter UI Elements
- **Toggle button:** `#filter-toggle` — `toggleFilters()` persists visibility to localStorage
- **Active button style:** `.filter-btn.active` (accent background)
- **Expand button:** `#expand-btn` opens `#expand-menu` dropdown

---

## Stats Bar

**Element:** `#stats-line`

Four stat counters with labeled values:

| Stat | DOM ID | Color | Source |
|---|---|---|---|
| Sessions | `#s-sessions` | text | `globalStats.sessions` |
| LLM Calls | `#s-llm` | assistant (purple) | `globalStats.llmCalls` |
| Tool Calls | `#s-tools` | tool (amber) | `globalStats.toolCalls` |
| Errors | `#s-errors` | error (red) | `globalStats.errors` |

### How Stats Are Aggregated

`globalStats` is updated throughout `handleGatewayMsg()`:
- `toolCalls++` — on `tool_start` events (from `event.added`, `session.sync`, `session.tool`)
- `llmCalls++` — on `run_start` events (from `event.added`, `session.sync`, `session.tool`)
- `errors++` — on `run_error` events (from `event.added`, `session.sync`, `session.tool`)
- `sessions++` / `sessions--` — on `sessions.changed` (created/loaded/ended/deleted)
- Reset to 0 on `reset` gateway message

---

## Sidebar

### Session List (`#session-list`)

Each session renders as a `.session-item` div with:

```
.session-item[.active][.optimistic][.failed]
  .sk
    .sk-text          → shortened session key (45 char max)
    .delete-btn       → 🗑 (only shown on hover, only for active session)
  .meta
    LLM count (assistant color)
    tool count (tool color)
    token sum (accent color, toLocaleString)
    error count (error color)
    .time             → absolute locale time (toLocaleTimeString)
```

**Time format:** `sess.lastTs.toLocaleTimeString()` — e.g. `"5:44:30 PM"` (NOT relative time).

### Sorting
Sessions sorted descending by `lastTs` (most recently active first).

### Active Session Highlight
```css
.session-item.active {
  background: #1e1f2e;
  border-left: 3px solid var(--accent);
}
```

### Delete Button
- Only visible on hover (opacity 0 → 1)
- Only shown on the currently active session
- Calls `deleteSessionFromList(sk)` with confirmation dialog
- Uses `deletedSessions` Set to prevent re-creation from in-flight events

### Session Count Badge
`#session-count` shows `sessions.size`

### Sidebar Collapse Toggle
- `toggleSidebar()` toggles `.collapsed` class on `#sidebar`
- Persisted in localStorage (`sidebarCollapsed`)
- On mobile (`window.innerWidth <= 600`): shows backdrop overlay
- Arrow button: `‹` when open, `›` when collapsed

### New Session Button
`+` button in sidebar header → `showNewSessionModal()`

### Delete Session Button (header)
`#delete-session-btn` — 🗑 icon, only visible when `activeSession` is set

---

## Content Area

### Content Header (`#content-header`)
- **Title:** session key (truncated at 60 chars) + total tokens badge + model badge
- **Buttons:**
  - `#filter-toggle` — toggle filters bar visibility
  - `#new-session-btn` — `sendNewSession()` (`🆕 New Session`)
  - `#stop-btn` — `stopSession()` (`⏹ Stop`)
  - `#clear-session-btn` — `clearSessionEvents()` (`🗑 Clear`)

### Messages Panel (`#messages`)
- Scrollable container for all event rendering output
- 6px custom scrollbar (track transparent, thumb var(--border))
- Contains: `.msg`, `.compact-row`, `.tc-wrap`, `.tr-wrap`, `.session-divider`, `.load-more-sessions`

### "↓ New Messages" Button (`#new-msg-btn`)
- Fixed position: bottom of messages area, centered
- Shows when `pendingNewMessages > 0` (new events arrived while scrolled up)
- Click → `scrollToBottom(true)` → clears scroll-up state
- Text: `"↓ N new messages"` or `"↓ New messages"`

---

## Chat Input

### Textarea (`#chat-input`)
- Placeholder: `"Type a message to send to the agent... (Shift+Enter for new line)"`
- Font: monospace, 12px
- Min-height: 60px, max-height: 500px, resizable vertically
- **Enter** → `handleSendOrStop()` (unless Shift is held)
- Disabled during pending request (`_pendingRequest === true`)

### Send Button (`#send-btn`)
State machine:
| State | Text | Background | Disabled |
|---|---|---|---|
| Idle | `Send` | `var(--accent)` | No |
| Sending (0–800ms) | `Sending...` | `var(--muted)` | Yes |
| Sending (800ms+) | `⏹ Stop` | `var(--error)` | No |

### History Button (`#history-btn`)
- 📜 icon
- Opens `#history-modal` with localStorage-backed message history
- `.has-history` class when history is non-empty (accent color)

### Resize Handle (`#resize-handle`)
- Draggable bar between messages area and chat input
- 6px tall, ns-resize cursor
- Resizes `#chat-input-container` height (60px–500px)

### Input Status Bar (`#input-status`)
- 18px tall bar below chat input
- Hidden by default (`display: none`)
- Shown during pending request: `"Agent is thinking..."` with pulsing dot animation
- Managed by `updateInputStatus()`

---

## Pending/Optimistic Request State Machine

### Variables
- `_pendingRequest: boolean` — gate between idle and sending states
- `_pendingSentMsg: string` — text of last sent message
- `_lastSentSessionKey: string` — session where message was sent
- `_lastActivityTs: number` — timestamp for timeout awareness

### Flow: `sendChatMessage()`

```
1. Guard: reject if _pendingRequest, no WS, or empty msg
2. Save draft to session
3. Pre-clean: remove stale canonical user_text with same text from session events
4. Create optimistic user_text event (pending: true, source: 'local')
5. Push to sess.events, set _renderedCount = 0 (force full rebuild)
6. Set _pendingRequest = true, _pendingSentMsg = msg
7. Update UI: disable input, button → "Sending..." (muted)
8. Send WS message: { type: 'chat', message: msg, sessionKey: sk }
9. Clear textarea, save to input history
10. After 800ms: inject loading placeholder event
11. After 800ms: button → "⏹ Stop" (red, enabled)
12. After 60s: if still pending and no activity → inject run_error, clearPendingState()
```

### Flow: `clearPendingState()`
```
1. _pendingRequest = false
2. Remove all loading events from active session
3. Restore send button to "Send" (accent)
4. Re-enable input
5. Hide input status bar
```

### Flow: `upgradePendingMessages(sess)`
```
1. Find all user_text events with pending: true
2. Set pending: false, delivered: true
3. Force sess._renderedCount = 0 (full rebuild)
```

### Flow: `removeLoadingPlaceholders(sess)`
```
1. Remove all events with type === 'loading'
2. Force sess._renderedCount = 0
```

### Edge Cases Handled
- **Page refresh ghost:** Stale canonical user_text with same text (from disk load) is pre-cleaned before optimistic injection
- **Gateway echo dedup:** When `event.added` arrives with matching user_text, the local copy is upgraded and the server copy is dropped
- **Double-delivery race:** Fallback text dedup in `event.added` handler checks all existing user_text events by exact text match
- **60s timeout:** If no response activity within 60s of send, injects a `run_error` and clears pending state
- **Multi-send guard:** `_pendingRequest` blocks `sendChatMessage()` while a request is in flight
- **Session switch:** `clearPendingState()` called on session switch to reset state

### Button State: `handleSendOrStop()`
```js
if (_pendingRequest) {
  stopSession();      // Abort via sessions.abort WS message
  clearPendingState(); // Reset UI
} else {
  sendChatMessage();
}
```

---

## Session Boundary Lazy Load

### System Overview
Long-running sessions are divided into "boundaries" marked by `gateway-injected` `run_start` events. The UI lazily loads older boundaries.

### State
- `sess._visibleBoundaries: number` — how many boundaries to show (default: 1)

### Rendering Logic (in `showSessionContent()`)
```js
const maxBoundaries = sess._visibleBoundaries || 1;
let boundaryCount = 0;
let sliceFrom = 0;
for (let i = eventsWithCum.length - 1; i >= 0; i--) {
  if (ev.type === 'run_start' && ev.model === 'gateway-injected') {
    boundaryCount++;
    if (boundaryCount === maxBoundaries) { sliceFrom = i; break; }
  }
}
// Render only events from sliceFrom onwards
```

### "Load Previous Session" Button
- Appears at top when `sliceFrom > 0`
- CSS class: `.load-more-sessions` (accent color, full-width, clickable)
- Calls `loadPreviousSessionBoundary()` which:
  - Increments `sess._visibleBoundaries`
  - Resets `sess._renderedCount` to 0
  - Invalidates filter cache
  - Triggers full UI rebuild

---

## New Session Modal

### Trigger
- `+` button in sidebar header → `showNewSessionModal()`
- `🆕 New Session` button in content header → `sendNewSession()` (shortcut, no modal)

### Form Fields
| Field | Element | Description |
|---|---|---|
| Agent | `#new-session-agent` (select) | Options: `agent:main:main` (main), `agent:personal:main` (personal) |
| Session Name | `#new-session-name` (input) | Optional; custom name overrides default |
| Initial Message | `#new-session-msg` (input) | Optional; sent after session creation |

### Session Key Generation
```js
if (customName) {
  // Use: agent:instance:customName
  sessionKey = base + ':' + customName;
} else if (exists) {
  // Append -timestamp suffix for uniqueness
  sessionKey = agent + '-' + Date.now().toString(36).slice(-6);
} else {
  sessionKey = agent;
}
```

### Optimistic Flow
1. Send `sessions.create` WS message
2. Immediately add optimistic session to `sessions` Map with `_optimistic: true`
3. Show spinner in modal ("Creating session...")
4. Poll every 200ms (up to 50 tries = 10s) for `_optimistic` to clear
5. On confirmation: close modal
6. On timeout: mark session as `_failed`, close modal, update UI

### Optimistic Session UI
- `.session-item.optimistic` — opacity 0.5, not clickable, shows "🔄 Creating..."
- `.session-item.failed` — opacity 0.5, shows "⚠️ Failed"

---

## JSON Viewer Modal

### Trigger
Clicking any event badge or the `{ } JSON` button on tool call/result headers.

### Implementation
- `showJsonViewer(idx)` — looks up event by index in `sessionEvents`, stringifies with 2-space indent
- `closeJsonViewer(e)` — closes on backdrop click or ✕ button
- `copyJsonViewer()` — copies JSON to clipboard
- **Modal background dismiss:** clicking outside the modal content calls `closeJsonViewer()`

### Structure
```
#json-viewer-modal (fixed, fullscreen, dark backdrop, z-index: 2000)
  .modal-inner
    header: "📋 Event JSON" + ✕ close button
    pre#json-viewer-content (scrollable, monospace, white-space: pre-wrap)
    footer: 📋 Copy + Close buttons
```

---

## Input History Modal

### Storage
- `localStorage` key: `'deepclaw-ui-input-history'`
- Max items: 50
- Deduplicated (recent entry moved to top)

### Implementation
- `saveInputToHistory(msg)` — called after every sent message
- `getInputHistory()` — returns parsed array
- `toggleHistory()` — show/hide modal
- `showHistoryModal()` — renders list items, each clickable to populate input
- `clearHistory()` — confirmation dialog, clears localStorage

### Structure
```
#history-modal (fixed, dark backdrop, z-index: 1000)
  .modal-content
    h3: "📜 Message History" + ✕
    #history-list
      .history-item × N (clickable, hover highlight)
    #history-clear (red, clear all)
```

---

## Clear Session Events

### Trigger
`🗑 Clear` button in content header → `clearSessionEvents()`

### Flow
1. `POST /api/session/:key/clear-events`
2. `GET /api/session/:key` to fetch fresh state
3. Replaces `sess.events` with fetched data
4. Resets `_renderedCount`, `_visibleBoundaries`, token counts
5. Invalidates filter cache, triggers full UI rebuild

---

## Stop Session

### Trigger
`⏹ Stop` button in content header → `stopSession()`

### Flow
1. Sends WS message: `{ type: 'req', method: 'sessions.abort', params: { key: activeSession } }`
2. Calls `clearPendingState()` to reset UI

---

## Delete Session

### Trigger
- `🗑` button in sidebar header → `deleteActiveSession()`
- `.delete-btn` on hover of active session item → `deleteSessionFromList(sk)`

### Flow
1. Confirmation dialog (for list item deletion)
2. `POST /api/session/:key/delete`
3. Removes from `sessions` Map
4. Adds to `deletedSessions` Set
5. Clears `activeSession` if needed
6. Updates stats

---

## rAF Throttle: `scheduleUIUpdate(forceList, forceContent)`

**Location:** Section 3, lines ~530–543

Batches multiple `updateUI()` calls into a single `requestAnimationFrame`:

```js
function scheduleUIUpdate(forceList, forceContent) {
  if (forceList) _updateForceList = true;
  if (forceContent) _updateForceContent = true;
  if (_updateScheduled) return;
  _updateScheduled = true;
  requestAnimationFrame(() => {
    _updateScheduled = false;
    const fl = _updateForceList;
    const fc = _updateForceContent;
    _updateForceList = false;
    _updateForceContent = false;
    updateUI(fl, fc);
  });
}
```

- If a full session list refresh is requested, `_updateForceList` stays true
- If a full content refresh is requested, `_updateForceContent` stays true
- Only one rAF callback runs per frame, regardless of how many times `scheduleUIUpdate()` is called

---

## CSS Custom Properties (Theme)

```css
:root {
  --bg: #0f1117;         /* Main background */
  --panel: #161922;      /* Panel/sidebar background */
  --border: #2a2d3a;     /* Borders */
  --text: #e4e4e7;       /* Primary text */
  --muted: #71717a;      /* Muted/secondary text */
  --accent: #6366f1;     /* Accent (indigo) */
  --user: #22c55e;       /* User message color (green) */
  --assistant: #818cf8;  /* Assistant message color (purple-blue) */
  --tool: #f59e0b;       /* Tool call color (amber) */
  --error: #ef4444;      /* Error color (red) */
  --info: #38bdf8;       /* Info color (light blue) */
}
```

### Key CSS Class Families

| Family | Classes | Purpose |
|---|---|---|
| `.msg-*` | `.msg-user`, `.msg-assistant`, `.msg-thinking`, `.msg-run-start`, `.msg-run-end`, `.msg-run-error`, `.msg-system` | Full event message cards |
| `.role-*` | `.role-user`, `.role-assistant`, `.role-system`, `.role-error` | Event type badges |
| `.tc-*` | `.tc-wrap`, `.tc-header`, `.tc-body`, `.tc-meta`, `.tc-cmd`, `.tc-path`, `.tc-preview`, `.tc-name`, `.tc-chev`, `.tc-actions`, `.tc-action-btn`, `.tc-copy-path`, `.tc-task-body`, `.tc-expanded`, `.tc-exec` | Tool call renderer |
| `.tr-*` | `.tr-wrap`, `.tr-header`, `.tr-body`, `.tr-code`, `.tr-tag`, `.tr-detail`, `.tr-time`, `.tr-expanded`, `.tr-error`, `.tr-stderr`, `.tr-actions`, `.tr-action-btn`, `.tr-output-stats`, `.tr-cmd`, `.tr-code-error` | Tool result renderer |
| `.compact-*` | `.compact-row`, `.compact-user`, `.compact-assistant`, `.compact-thinking`, `.compact-run-start`, `.compact-error`, `.compact-tag`, `.compact-content`, `.compact-sep` | Compact mode rows |
| `.md-content` | (single class) | Markdown-rendered content wrapper |
| `.syn-*` | `.syn-kw`, `.syn-str`, `.syn-cmt`, `.syn-num` | Syntax highlighting tokens |
| `.diff-*` | `.diff-add`, `.diff-rem`, `.diff-hdr` | Diff rendering |
| `.plan-step` | `.plan-step.completed`, `.plan-step.in-progress`, `.plan-step.pending` | Plan step items |
| `.mem-card` | `.mem-card`, `.mem-card .path`, `.mem-card .score` | Memory search result cards |
| `.session-*` | `.session-item`, `.session-item.active`, `.session-item.optimistic`, `.session-item.failed`, `.session-divider` | Session list items + dividers |
| `.load-more-sessions` | (single class) | Lazy load button |
| `.expand-menu-*` | `.expand-menu-item`, `.expand-menu-item.checked`, `.expand-menu-section` | Expand/collapse dropdown |
| `.msg.pending` / `.msg.delivered` / `.msg.loading` | Pending/delivered/loading message states |

---

## Event Dedup Patterns

### Backend: `_seenMsgHashes` (per-session Set)
```js
function getMsgHash(role, content) {
  return role + '|' + hashStringForMsg(content.trim());
}
function isSeenMessage(sess, role, content) {
  const h = getMsgHash(role, content);
  if (sess._seenMsgHashes.has(h)) return true;
  sess._seenMsgHashes.add(h);
  if (sess._seenMsgHashes.size > 1000) {
    // Prune to last 500
    sess._seenMsgHashes = new Set(Array.from(sess._seenMsgHashes).slice(-500));
  }
  return false;
}
```

### Frontend: `hasExistingTextEvent(events, runId, text, type)`
- Exact match: same runId, same type, same text
- Overlap match: text is a subset or superset of existing event text

### User Text Dedup (in `handleGatewayMsg` `event.added`)
1. Check for local pending copy → upgrade and drop server copy
2. Fallback: check all existing user_text events for exact text match
3. Remove stale canonical events with same text (page-refresh ghost fix)

### Streaming Merge (in `handleGatewayMsg` `event.added`)
- `assistant_text`: scans backwards for same runId → replaces text
- `thinking`: scans backwards for same runId → appends text
- `tool_result`: scans backwards for same toolCallId+runId → appends result
- `tool_start`, `run_start`, `run_end`, `run_error`: scan for duplicate → skip

---

## localStorage Keys

| Key | Content | Updated By |
|---|---|---|
| `deepclaw-ui-prefs` | `{ filtersVisible, expandedItems, lastActiveSession, sidebarCollapsed }` | `savePrefs()` |
| `deepclaw-ui-input-history` | `string[]` (max 50) | `saveInputToHistory()` |
