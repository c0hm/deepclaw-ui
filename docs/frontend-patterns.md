# Frontend Implementation Patterns

> **Common patterns and conventions used in the DeepClaw UI codebase**  
> Reference for coder agents working on this project

---

## 1. Renderer Dispatch Pattern

**Concept:** A top-level function routes events by type, delegating to specialized renderers. Each specialized renderer handles one event type with full knowledge of its data shape.

### Structure
```
renderEvent(ev, idx, forceExpand)    ← Main dispatcher
  ├── ev.type === 'tool_start'       → renderToolCall(ev, idx, forceExpand)
  │     ├── ev.toolName === 'exec'   → renderExecCall(ev, inp, idx)
  │     ├── ev.toolName === 'read'   → renderReadCall(ev, inp, idx)
  │     └── ...                      → 10+ per-tool call renderers
  ├── ev.type === 'tool_result'      → renderToolResult(ev, idx, forceExpand)
  │     ├── ev.toolName === 'exec'   → renderExecHeader(ev, parsed, t, idx)
  │     └── ...                      → 8+ per-tool result header renderers
  ├── ev.type === 'thinking'         → inline HTML (thinking card)
  ├── ev.type === 'assistant_text'   → inline HTML (with renderMarkdown)
  └── ...
```

### When to Use
- When an event type has significantly different visual requirements
- When there are many event sub-types that share a wrapper but differ in content
- When adding a new event type to the system

### Implementation
```js
function renderEvent(ev, idx, forceExpand) {
  // Common logic (if any) — timestamps, shared classes

  if (ev.type === 'tool_start') {
    return renderToolCall(ev, idx, !!forceExpand);
  }
  if (ev.type === 'tool_result') {
    return renderToolResult(ev, idx, !!forceExpand);
  }
  // ... more types

  return ''; // Unknown type: render nothing
}
```

---

## 2. Per-Tool Renderer Convention

**Concept:** Each tool has TWO renderers — one for the call (input), one for the result (output).

### Call Renderer Convention
```js
function renderXxxCall(ev, inp, idx) {
  // 1. Extract fields from inp (parsed ev.input)
  // 2. Build header line: icon + tc-name + preview + chevron
  // 3. Build metadata rows for tc-meta grid
  // 4. Return tc-wrap div with tc-header + buildTcBody(rows, actions)
  return '' +
    '<div class="tc-wrap[.tc-special-class]">' +
      '<div class="tc-header" onclick="toggleToolCall(this,' + idx + ')">' +
        header +
      '</div>' +
      buildTcBody(metaRows, actionsHtml) +
    '</div>';
}
```

### Result Renderer Convention
```js
function renderXxxHeader(ev, parsed, t, idx, expanded) {
  // 1. Extract details from parsed (envelope-parsed result)
  // 2. Look up matching tool_start for file paths / command (scan sessionEvents)
  // 3. Build status tags (OK/ERROR, exit codes, etc.)
  // 4. Build detail line with key metadata
  // 5. Determine expand class (expanded || isError)
  // 6. Return tr-wrap div with tr-header + tr-body
  return '' +
    '<div class="tr-wrap[.tr-expanded][.tr-error]" data-idx="' + idx + '">' +
      '<div class="tr-header" onclick="toggleToolResult(this.parentElement,' + idx + ')">' +
        // tag + detail + time
      '</div>' +
      '<div class="tr-body">' +
        // content + actions (copy, json)
      '</div>' +
    '</div>';
}
```

### Shared Helpers
- `buildTcBody(metaRows, actionsHtml)` — meta grid + action buttons for calls
- `renderToolBody(ev, parsed, idx)` — code block + action buttons for results
- `tcJsonBtn(idx)` / `tcCopyBtn(text)` — action buttons
- `parseCallInput(ev)` — safe input parsing
- `parseToolResult(resultStr)` — envelope-aware result parsing

---

## 3. Expand/Collapse Toggle Pattern

**Concept:** Two independent expand/collapse systems coexist:
1. **Programmatic** (`_expandedItems` Set) — controls initial render state
2. **User-click** (`toggleToolCall`/`toggleToolResult`) — CSS class toggle

### Programmatic System
```js
// State
let _expandedItems = new Set(['user', 'response']); // persisted to localStorage

// Decision
function isExpanded(ev) {
  if (ev.type === 'tool_result' && ev.toolName === 'update_plan') return false;
  if (ev.type === 'tool_start' || ev.type === 'tool_result')
    return _expandedItems.has(ev.toolName);
  if (ev.type === 'thinking') return _expandedItems.has('thinking');
  if (ev.type === 'user_text') return _expandedItems.has('user');
  if (ev.type === 'assistant_text') return _expandedItems.has('response');
  return true; // run_error, loading, etc.
}
```

### User-Click System
```js
// Tool results: CSS class toggle
function toggleToolResult(el, idx) {
  el.classList.toggle('tr-expanded');
}

// Tool calls: CSS class toggle
function toggleToolCall(el, idx) {
  el.parentElement.classList.toggle('tc-expanded');
}
```

### Expand Menu Pattern
```js
function toggleExpandMenu(e) {
  e.stopPropagation();
  const menu = document.getElementById('expand-menu');
  const wasVisible = menu.classList.contains('visible');
  closeExpandMenu();  // always close first
  if (!wasVisible) {
    updateExpandMenu();  // rebuild menu with current state
    menu.classList.add('visible');
  }
}

// Click-outside-to-close
document.addEventListener('click', function(e) {
  if (!button.contains(e.target) && !menu.contains(e.target)) {
    closeExpandMenu();
  }
});
```

### Key Points
- `_expandedItems` is persisted in localStorage under `deepclaw-ui-prefs`
- Changing an expand item triggers a full re-render (`_renderedCount = 0`)
- Special case: `update_plan` tool results are NEVER programmatically expanded
- `forceExpand` parameter bypasses the decision and renders expanded

---

## 4. rAF Throttle Pattern

**Concept:** High-frequency UI updates (from WebSocket events) are batched into one `requestAnimationFrame` callback per frame.

### Implementation
```js
let _updateScheduled = false;
let _updateForceList = false;
let _updateForceContent = false;

function scheduleUIUpdate(forceList, forceContent) {
  if (forceList) _updateForceList = true;    // accumulate flags
  if (forceContent) _updateForceContent = true;
  if (_updateScheduled) return;              // already scheduled
  _updateScheduled = true;
  requestAnimationFrame(() => {
    _updateScheduled = false;
    const fl = _updateForceList;
    const fc = _updateForceContent;
    _updateForceList = false;
    _updateForceContent = false;
    updateUI(fl, fc);                        // single update per frame
  });
}
```

### Usage
```js
ws.onmessage = (e) => {
  handleGatewayMsg(msg);
  scheduleUIUpdate(); // no force flags — only refresh if counts changed
};

// For structural changes:
scheduleUIUpdate(true);       // force session list refresh
scheduleUIUpdate(false, true); // force content refresh
scheduleUIUpdate(true, true);  // force both
```

### When to Force Refresh
- `forceList = true`: session added/removed, stats changed
- `forceContent = true`: events changed in viewed session, filter changed, expand toggle

---

## 5. Pending/Optimistic Message Pattern

**Concept:** User messages are shown immediately with a `pending` state, then upgraded to `delivered` when the server confirms. A loading placeholder provides visual feedback during wait.

### State Variables
```js
let _pendingRequest = false;       // global gate
let _pendingSentMsg = null;        // text of sent message for dedup
let _lastSentSessionKey = null;    // session where message was sent
let _lastActivityTs = 0;           // for timeout calculation
```

### Lifecycle
```
               User clicks Send
                      │
                      ▼
         ┌─────────────────────────┐
         │ 1. Inject optimistic    │
         │    user_text (pending)  │
         │ 2. Set _pendingRequest  │
         │ 3. Disable input        │
         │ 4. Button → "Sending..." │
         └───────────┬─────────────┘
                     │ 800ms delay
                     ▼
         ┌─────────────────────────┐
         │ 5. Inject loading       │
         │    placeholder event    │
         │ 6. Button → "⏹ Stop"   │
         └───────────┬─────────────┘
                     │
          ┌──────────┼──────────┐
          ▼          ▼          ▼
    run_start    run_end    60s timeout
    arrives     arrives    (no activity)
          │          │          │
          ▼          ▼          ▼
    upgrade    clear       inject
    pending    pending     run_error
    messages   state       + clear
```

### Gateway Echo Dedup
When `event.added` delivers a `user_text`:
1. Check if we have a local pending copy (`_pendingSentMsg` matches) → upgrade pending → drop server copy
2. Check all existing user_text for exact text match → skip if found
3. Otherwise → accept as new (from another tab)

### Key Implementation Details
- **Pre-clean:** Before injecting optimistic event, remove stale canonical events with same text (page-refresh ghost fix)
- **Full rebuild on mutation:** Any modification to `sess.events` that adds/removes items sets `_renderedCount = 0` to force full render
- **Timeout:** 60s after send, if no `_lastActivityTs` update, inject a `run_error`

---

## 6. Session Boundary Lazy-Load Pattern

**Concept:** Long sessions are divided by `gateway-injected` markers. Only the N most recent boundaries are rendered; older ones are loaded on demand.

### State
```js
sess._visibleBoundaries = 1; // default: show 1 boundary
```

### Render Slicing
```js
// In showSessionContent():
let boundaryCount = 0;
let sliceFrom = 0;
for (let i = events.length - 1; i >= 0; i--) {
  if (ev.type === 'run_start' && ev.model === 'gateway-injected') {
    boundaryCount++;
    if (boundaryCount === maxBoundaries) { sliceFrom = i; break; }
  }
}
const rendered = sliceFrom > 0 ? events.slice(sliceFrom) : events;
```

### Load More
```js
function loadPreviousSessionBoundary() {
  sess._visibleBoundaries++;
  sess._renderedCount = 0;  // force full rebuild
  scheduleUIUpdate(true, true);
}
```

### UI Element
```html
<div class="load-more-sessions" onclick="loadPreviousSessionBoundary()">
  ⬆ Load Previous Session
</div>
```

Rendered at the top of the event list when `sliceFrom > 0`.

---

## 7. localStorage Preference Pattern

**Concept:** UI preferences are persisted across page reloads with a single JSON object.

### Storage Format
```json
{
  "filtersVisible": false,
  "expandedItems": ["user", "response", "exec", "read"],
  "lastActiveSession": "agent:main:main",
  "sidebarCollapsed": false
}
```

### Implementation
```js
const _PREFS_KEY = 'deepclaw-ui-prefs';

function savePrefs() {
  try {
    localStorage.setItem(_PREFS_KEY, JSON.stringify({
      filtersVisible,
      expandedItems: [..._expandedItems],  // Set → Array
      lastActiveSession: _lastActiveSession,
      sidebarCollapsed
    }));
  } catch { /* quota or disabled */ }
}

function loadPrefs() {
  try {
    const raw = localStorage.getItem(_PREFS_KEY);
    if (!raw) return;
    const p = JSON.parse(raw);
    if (typeof p.filtersVisible === 'boolean') filtersVisible = p.filtersVisible;
    if (Array.isArray(p.expandedItems)) _expandedItems = new Set(p.expandedItems);
    if (typeof p.lastActiveSession === 'string') _lastActiveSession = p.lastActiveSession;
    if (typeof p.sidebarCollapsed === 'boolean') sidebarCollapsed = p.sidebarCollapsed;
  } catch { /* corrupt, ignore */ }
}
```

### Auto-Select Last Session
```js
function tryAutoSelect() {
  if (_autoSelectAttempted) return;
  if (!_lastActiveSession) return;
  if (activeSession) return;
  if (!sessions.has(_lastActiveSession)) return;
  _autoSelectAttempted = true;
  showSession(_lastActiveSession);
}
```

Called from WebSocket `onopen` (after initial session sync) and from `session.summary`/`session.sync` handlers.

---

## 8. Modal Lifecycle Pattern

**Concept:** Modals follow a create-show-close-destroy lifecycle, using CSS display toggling.

### Pattern
```js
// Show
function showXxxModal() {
  document.getElementById('xxx-modal').style.display = 'flex';
  // Populate content
  // Focus first input
}

// Close
function closeXxxModal() {
  document.getElementById('xxx-modal').style.display = 'none';
  // Reset form fields
}

// Dismiss on backdrop click
modal.addEventListener('click', (e) => {
  if (e.target === modal) closeXxxModal();
});

// Dismiss on Escape
document.addEventListener('keydown', (e) => {
  if (e.key === 'Escape') closeXxxModal();
});
```

### Modals in Use
| Modal | ID | Open | Close | Z-Index |
|---|---|---|---|---|
| JSON Viewer | `#json-viewer-modal` | `showJsonViewer(idx)` | `closeJsonViewer(e)` | 2000 |
| Input History | `#history-modal` | `toggleHistory()` | `toggleHistory()` | 1000 |
| New Session | `#new-session-modal` | `showNewSessionModal()` | `closeNewSessionModal()` | 1000 |

### Optimistic Modal (New Session)
The new session modal uses an optimistic pattern:
1. Show modal
2. Send WS message
3. Keep modal open with spinner
4. Poll every 200ms for confirmation (max 10s)
5. On confirmation → close modal
6. On timeout → mark session failed, close modal

---

## 9. CSS Custom Property Theme System

**Concept:** All colors are defined as CSS custom properties on `:root`, making them globally configurable.

```css
:root {
  --bg: #0f1117;
  --panel: #161922;
  --border: #2a2d3a;
  --text: #e4e4e7;
  --muted: #71717a;
  --accent: #6366f1;
  --user: #22c55e;
  --assistant: #818cf8;
  --tool: #f59e0b;
  --error: #ef4444;
  --info: #38bdf8;
}
```

### Semantic Color Usage
| Variable | Semantic Meaning | Used For |
|---|---|---|
| `--accent` | Primary action color | Buttons, active states, special badges, links |
| `--user` | User messages | Border-left, role badges, compact tags |
| `--assistant` | Assistant/LLM responses | Border-left, role badges, model metadata |
| `--tool` | Tool calls | Border-left, tool tags, compact tags |
| `--error` | Errors | Border-left, error badges, error text |
| `--info` | Information/runs | Run start border, diff headers, file links |
| `--muted` | Secondary/deemphasized | Timestamps, compact text, detail text |
| `--text` | Primary text | Content text, headers |
| `--bg` | Page background | Body, inputs |
| `--panel` | Panel backgrounds | Sidebar, header, content header, modals |
| `--border` | Borders and dividers | All borders, scrollbar thumbs |

---

## 10. Event Dedup Patterns

### Backend: Hash-Based Dedup (per-session)
```js
let _seenMsgHashes = new Set();

function hashStringForMsg(str) {
  let hash = 0;
  for (let i = 0; i < str.length; i++) {
    hash = ((hash << 5) - hash) + str.charCodeAt(i);
    hash |= 0;
  }
  return hash.toString(36);
}

function getMsgHash(role, content) {
  if (!content) return null;
  return role + '|' + hashStringForMsg(content.trim());
}

function isSeenMessage(sess, role, content) {
  const h = getMsgHash(role, content);
  if (sess._seenMsgHashes.has(h)) return true;
  sess._seenMsgHashes.add(h);
  // Keep Set bounded to 1000 entries (prune to 500)
  if (sess._seenMsgHashes.size > 1000) {
    const arr = Array.from(sess._seenMsgHashes);
    sess._seenMsgHashes = new Set(arr.slice(-500));
  }
  return false;
}
```

### Frontend: Text-Based Dedup
```js
function hasExistingTextEvent(events, runId, text, type) {
  if (!text) return false;
  const trimmed = text.trim();
  if (!trimmed) return false;
  // Exact match: same runId and type
  for (const ev of events) {
    if (ev.type === type && ev.runId === runId) {
      if (ev.text && ev.text.length >= trimmed.length) return true;
    }
  }
  // Overlap match: text is subset/superset of existing
  for (const ev of events) {
    if (ev.type === type && ev.text && ev.runId === runId) {
      const evText = ev.text.trim();
      if (evText.includes(trimmed) || trimmed.includes(evText)) return true;
    }
  }
  return false;
}
```

---

## 11. Incremental Rendering Pattern

**Concept:** Instead of rebuilding the entire event list on every update, new events are appended via `DocumentFragment` when only additions occur.

### State Tracking
```js
sess._renderedCount = 0; // reset on structural changes
```

### Decision Logic
```js
if (filterChanged || newCount < prevCount || prevCount === 0) {
  // FULL REBUILD — filter changed or events removed
  msgsEl.innerHTML = fullHtml;
  // Preserve scroll position proportionally
} else if (newCount > prevCount) {
  // INCREMENTAL APPEND — only new events
  const frag = document.createDocumentFragment();
  const newEvents = events.slice(prevCount);
  // ... render new events into container.innerHTML
  while (container.firstChild) frag.appendChild(container.firstChild);
  msgsEl.appendChild(frag);
}
```

### When to Force Full Rebuild
Set `sess._renderedCount = 0` when:
- Filter changes
- Events are removed (clear, delete, upgrade)
- Expand/collapse toggle changes
- Session boundary lazy-load changes
- Session switch

---

## 12. Scroll Position Preservation Pattern

**Concept:** When doing a full rebuild (e.g., filter change, expand toggle), the scroll position is proportionally preserved.

```js
const prevScrollTop = msgsEl.scrollTop;
const prevScrollHeight = msgsEl.scrollHeight;
msgsEl.innerHTML = newHtml;
if (prevScrollHeight > 0 && msgsEl.scrollHeight > 0) {
  msgsEl.scrollTop = Math.round(prevScrollTop * msgsEl.scrollHeight / prevScrollHeight);
}
```

---

## 13. Event-Streaming Merge Pattern

**Concept:** During active streaming, new chunks of the same event type are merged into existing events rather than creating duplicates.

### Implementation (in `handleGatewayMsg` `event.added`)
```js
// Assistant text: replace (not append) — full text is sent each time
if (ev.type === 'assistant_text') {
  for (let i = sess.events.length - 1; i >= 0; i--) {
    const prev = sess.events[i];
    if (prev.type === 'assistant_text' && prev.runId === ev.runId) {
      prev.text = ev.text;  // replace
      prev.ts = ev.ts;
      return;
    }
    if (prev.type === 'assistant_text' || prev.type === 'run_end' || prev.type === 'run_start')
      break;
  }
}

// Thinking: append (incremental chunks)
if (ev.type === 'thinking' && ev.runId) {
  for (let i = sess.events.length - 1; i >= 0; i--) {
    const prev = sess.events[i];
    if (prev.type === 'thinking' && prev.runId === ev.runId) {
      prev.text += ev.text;  // append
      prev.ts = ev.ts;
      return;
    }
    if (prev.type === 'assistant_text' || prev.type === 'run_end' || prev.type === 'run_start')
      break;
  }
}

// Tool result: append (streaming output)
if (ev.type === 'tool_result' && ev.runId) {
  for (let i = sess.events.length - 1; i >= 0; i--) {
    const prev = sess.events[i];
    if (prev.type === 'tool_result' && prev.toolCallId === ev.toolCallId && prev.runId === ev.runId) {
      prev.result += resultStr;  // append
      prev.ts = ev.ts;
      return;
    }
    if (prev.type === 'tool_start' || prev.type === 'run_end' || prev.type === 'run_start')
      break;
  }
}
```

---

## 14. Session Data Ingestion Pattern

**Concept:** Full session data arrives via `session.sync` gateway message. The handler performs dedup, cleanup, and filtering.

### Flow
```js
if (name === 'session.sync') {
  // 1. Reset session state
  sess.events = [];
  sess._seenMsgHashes = new Set();
  sess._renderedCount = 0;
  sess._visibleBoundaries = 1;

  // 2. Ingest token/model metadata
  // 3. Ingest events with timestamp conversion
  events.forEach(ev => {
    ev.ts = new Date(ev.ts);
    sess.events.push(ev);
    // Update globalStats counters
  });

  // 4. Filter corrupted user_text events
  //    (events with render HTML artifacts as text)
  sess.events = sess.events.filter(ev => {
    if (ev.type !== 'user_text') return true;
    if (ev.source === 'canonical' || ev.source === 'local') {
      // Drop if text contains render artifacts
      if (/👤 USER|msg-header|msg-role/.test(ev.text)) return false;
      return true;
    }
    return false;
  });

  // 5. Dedup canonical user_text by text+time window
  const seenUT = new Map();
  for (let i = sess.events.length - 1; i >= 0; i--) {
    const ev = sess.events[i];
    if (ev.type !== 'user_text' || ev.source !== 'canonical') continue;
    const key = ev.text.slice(0, 80) + '|' + Math.floor(ev.ts / 2000);
    if (seenUT.has(key)) {
      sess.events.splice(i, 1);
    } else {
      seenUT.set(key, true);
    }
  }

  // 6. Schedule UI update
  scheduleUIUpdate(true, true);
  tryAutoSelect();
}
```

---

## 15. Filter Cache Pattern

**Concept:** Filtered event lists are cached to avoid recomputing on every render.

```js
let _lastFilterHash = '';
let _filteredCache = [];
let _filteredCacheHash = '';

function getFilteredEvents(sess) {
  const filterHash = filter + '|' + filterText + '|' + sess.events.length;
  if (filterHash === _filteredCacheHash) return _filteredCache;

  _filteredCacheHash = filterHash;
  // ... compute filtered events ...
  _filteredCache = events;
  return events;
}
```

Cache is invalidated by:
- Setting `_filteredCacheHash = ''` (session switch, expand toggle, clear events)
- Changing `_lastFilterHash` (filter button click, text input)

---

## 16. Session Draft Preservation Pattern

**Concept:** When switching between sessions, the current chat input is saved as a draft and restored when switching back.

```js
function showSession(sk) {
  // Save draft of current session
  if (activeSession && sessions.has(activeSession)) {
    sessions.get(activeSession).draft = document.getElementById('chat-input').value;
  }

  // ... switch session ...

  // Restore draft of new session
  const sess = sessions.get(sk);
  if (sess && sess.draft !== undefined) {
    document.getElementById('chat-input').value = sess.draft;
  } else {
    document.getElementById('chat-input').value = '';
  }
}
```

---

## 17. Gateway Message Handling Pattern

**Concept:** `handleGatewayMsg(msg)` is the central message router. It uses a series of `if (name === ...)` checks to route messages to handlers.

### Message Types Handled
| Name | Handler | Purpose |
|---|---|---|
| `chat_ack` | Lightweight UI update | Backend ack |
| `chat_delivered` | Lightweight UI update | Gateway delivery confirmation |
| `sessions.changed` | Full session management | Create/end/delete sessions |
| `session.summary` | Metadata ingestion | Lightweight token/model data |
| `session.sync` | Full data ingestion | Complete session rebuild |
| `event.added` | Event append/merge | Real-time event streaming + dedup |
| `session.message` | Metadata update | Token/model updates + pending clear |
| `session.tokens` | Token update | Token count + context calculation |
| `session.cleared` | Event reset | Clear + re-fetch |
| `session.messages` | Dedup | Pre-populate `_seenMsgHashes` |
| `sessions.history` | Event creation | Convert history messages to events |
| `agent` | Counter increment | Legacy agent event |
| `chat` | run_end creation | Legacy chat completion |
| `heartbeat` | No-op | Ignored |
| `session.tool` | Legacy stream handling | Old-style tool/lifecycle/assistant streams |
| `reset` | Full state reset | Clear all sessions and stats |

---

## 18. Collapsible Sidebar Pattern (Responsive)

**Concept:** Sidebar can be collapsed via toggle button. On mobile, a backdrop overlay prevents interaction with content when sidebar is open.

```js
function isMobile() { return window.innerWidth <= 600; }

function toggleSidebar() {
  sidebarCollapsed = !sidebarCollapsed;
  savePrefs();
  if (sidebarCollapsed) {
    sidebar.classList.add('collapsed');
    backdrop.classList.remove('active');
    btn.textContent = '›';
  } else {
    sidebar.classList.remove('collapsed');
    if (isMobile()) backdrop.classList.add('active');
    btn.textContent = '‹';
  }
}
```

### CSS
```css
#sidebar.collapsed {
  transform: translateX(-100%);
  opacity: 0;
  visibility: hidden;
  border-right: none;
  width: 0;
  overflow: hidden;
}
#sidebar-backdrop.active {
  display: block;
  cursor: pointer;
}
```

---

## 19. Unified Diff Pattern

**Concept:** Render unified diff patches as a single-column color-coded view — removed lines in red, added lines in green, context lines in default color, hunk headers as dividers.

### When to Use
- When rendering `edit` tool results that include `details.patch` (a unified diff)
- When you need a simple, scannable diff view without side-by-side complexity

### Pipeline
```
raw patch string
     │
     ▼
renderUnifiedDiff(patch, filePath)  ← Simple line-by-line renderer
     │
     ▼
HTML injected into .tr-body
```

### Rendering: `renderUnifiedDiff(patchText, filePath)`

Produces a single-column layout:

```html
<div class="udiff">
  <div class="udiff-file"><span>📄</span> path/to/file</div>  <!-- optional, only if filePath -->
  <div class="udiff-hunk">@@ -1,3 +1,4 @@ ...</div>         <!-- hunk header -->
  <div class="udiff-rem">- removed line</div>                  <!-- red background -->
  <div class="udiff-add">+ added line</div>                    <!-- green background -->
  <div class="udiff-ctx"> context line</div>                   <!-- default color -->
</div>
```

### CSS Classes

| Class | Purpose |
|---|---|
| `.udiff` | Container (bordered, scrollable at 60vh, monospace) |
| `.udiff-file` | File path bar with 📄 icon |
| `.udiff-hunk` | Hunk header divider (info-colored, dark bg) |
| `.udiff-rem` | Removed lines (red bg + red text, `white-space: pre`) |
| `.udiff-add` | Added lines (green bg + green text, `white-space: pre`) |
| `.udiff-ctx` | Context lines (default text color, `white-space: pre`) |

### Integration in `renderEditHeader()`

```js
const patch = (d && typeof d.patch === 'string' && d.patch.trim()) ? d.patch : '';

// Priority order:
if (!isError && patch) {
  bodyContent += renderUnifiedDiff(patch, filePath);    // 1. Unified diff
} else if (!isError && d.edits) {
  // 2. Fallback: stacked preview blocks (existing)
} else if (!isError && diff) {
  // 3. Fallback: unified diff via renderDiff()
} else if (!isError && parsed.text) {
  // 4. Fallback: plain text
}
```

### Key Points
- Single-pass line-by-line — no intermediate parsing into structured hunks
- Container scrolled at 60vh max-height for large diffs
- File header only shown when `filePath` is truthy
- Skips git diff boilerplate (`diff --git`, `index`, `---`, `+++`) and `\ No newline` markers
- Patch overrides `details.edits` when both are present
- Error results always show the error box regardless of patch presence
- Pure JS, no external dependencies
