# Event Rendering Pipeline

> **Complete reference for the frontend event rendering system**  
> Covers: dispatch, per-tool renderers, markdown pipeline, compact mode, expand/collapse, scroll behavior

---

## Architecture Overview

The rendering system is a **dispatch-based pipeline** with three major phases:

1. **Filtering** — `getFilteredEvents(sess)` applies user filter and text search
2. **Compact/Expand Decision** — `showSessionContent()` decides per-event: compact row or full render
3. **Rendering** — `renderEvent(ev, idx, forceExpand)` dispatches to per-type renderers

There is no single flat `renderEvent()` that outputs raw HTML strings for all types. Instead, `renderEvent()` is a **router** that delegates to specialized sub-renderers.

---

## Dispatch: `renderEvent(ev, idx, forceExpand)`

**Location:** Section 22, lines ~2637–2758

```
renderEvent(ev, idx, forceExpand)
  ├── ev.type === 'tool_start'   → renderToolCall(ev, idx, !!forceExpand)
  ├── ev.type === 'tool_result'  → renderToolResult(ev, idx, !!forceExpand)
  ├── ev.type === 'thinking'     → inline msg-thinking card (truncated at 2000 chars)
  ├── ev.type === 'assistant_text' → msg-assistant card with renderMarkdown()
  ├── ev.type === 'user_text'    → msg-user card with pending/delivered CSS class
  ├── ev.type === 'loading'      → msg-loading placeholder card
  ├── ev.type === 'run_start'    → gateway-injected divider OR compact row OR full card
  ├── ev.type === 'run_end'      → compact ■ card with stop reason + token metadata
  └── ev.type === 'run_error'    → msg-run-error card with red error text
```

### Key differences from old docs:

| Event Type | Old Doc Says | Actual Code |
|---|---|---|
| `assistant_text` | `escHtml(text)` in `.msg-content` | `renderMarkdown(text)` in `.md-content` (rich HTML) |
| `tool_start` | Flat `tool-call` div with JSON dump | `renderToolCall()` → per-tool `tc-wrap` cards |
| `tool_result` | `↳ toolname` label + escHtml | `renderToolResult()` → per-tool `tr-wrap` headers |
| `run_start` badge | `▶ LLM START` | `▶` only, with separate `Σ total` badge + model name |
| `assistant_text` truncation | 3000 chars | **No truncation** — full text always rendered |

---

## Tool Call Rendering: `renderToolCall(ev, idx, forceExpand)`

**Location:** Section 21, lines ~2406–2668

Dispatches to per-tool call renderers based on `ev.toolName`:

```js
switch (ev.toolName) {
  case 'exec':           return renderExecCall(ev, inp, idx);
  case 'read':           return renderReadCall(ev, inp, idx);
  case 'edit':           return renderEditCall(ev, inp, idx);
  case 'write':          return renderWriteCall(ev, inp, idx);
  case 'update_plan':    return renderPlanCall(ev, inp, idx);
  case 'sessions_spawn': return renderSpawnCall(ev, inp, idx);
  case 'sessions_yield': return renderYieldCall(ev, inp, idx);
  case 'process':        return renderProcessCall(ev, inp, idx);
  case 'memory_search':  return renderMemSearchCall(ev, inp, idx);
  case 'memory_get':     return renderMemGetCall(ev, inp, idx);
  default:               return renderGenericCall(ev, inp, idx);
}
```

All call renderers produce a **`.tc-wrap`** container with:
- **`.tc-header`** — one-line clickable bar with tool icon, tool name, preview, chevron
- **`.tc-body`** — hidden by default, shown when `.tc-expanded` class is added
- **`.tc-meta`** — CSS grid of key/value metadata rows
- **`.tc-actions`** — Copy + JSON viewer buttons

### Per-Tool Call Renderers

#### `renderExecCall(ev, inp, idx)`
- **CSS class:** `tc-wrap tc-exec` (green border-left)
- **Header icons:** 🔧
- **Metadata:** command, workdir (shortened `~/...`), background flag, timeout, pty, elevated, env vars
- **Actions:** Copy command + JSON

#### `renderReadCall(ev, inp, idx)`
- **CSS class:** `tc-wrap`
- **Header icons:** 📄 with path, offset/limit info
- **Inline actions:** Copy path button, view-file (👁) button
- **Metadata:** file path, offset, limit
- **Actions:** Copy path + JSON

#### `renderEditCall(ev, inp, idx)`
- **CSS class:** `tc-wrap`
- **Header icons:** ✏️ with path + edit summary (`N edits (+A -R)`)
- **Inline actions:** Copy path, view-file
- **Metadata:** path, blocks count, per-block +/- line counts
- **Actions:** Copy path + JSON

#### `renderWriteCall(ev, inp, idx)`
- **CSS class:** `tc-wrap`
- **Header icons:** 📝 with path + content size
- **Inline actions:** Copy path, view-file
- **Metadata:** path, content size, preview (first 5 lines)
- **Actions:** Copy path + JSON

#### `renderPlanCall(ev, inp, idx)`
- **CSS class:** `tc-wrap`
- **Header icons:** 📋 with plan summary (`N/M steps · 🔄 X in progress`)
- **Metadata:** All plan steps with status icons (✅/🔄/⬜), explanation
- **Actions:** JSON only

#### `renderSpawnCall(ev, inp, idx)`
- **CSS class:** `tc-wrap` (auto-expanded if task > 200 chars)
- **Header icons:** 🚀 with task preview (first line, 80 chars) + model short name
- **Metadata:** full task body in `.tc-task-body` (max-height: 40vh, scrollable), taskName, model, cwd, context, timeout
- **Actions:** Copy task + JSON

#### `renderYieldCall(ev, inp, idx)`
- **CSS class:** `tc-wrap`
- **Header icons:** ⏳ with message preview (80 chars)
- **Metadata:** message
- **Actions:** JSON only

#### `renderProcessCall(ev, inp, idx)`
- **CSS class:** `tc-wrap`
- **Header icons:** 🔄 with action + sessionId
- **Metadata:** action, sessionId, timeout, limit, data, keys, text
- **Actions:** JSON only

#### `renderMemSearchCall(ev, inp, idx)`
- **CSS class:** `tc-wrap`
- **Header icons:** 🔍 with query preview (60 chars)
- **Metadata:** query, maxResults, minScore, corpus
- **Actions:** Copy query + JSON

#### `renderMemGetCall(ev, inp, idx)`
- **CSS class:** `tc-wrap`
- **Header icons:** 📖 with path + line range
- **Metadata:** path, from, lines, corpus
- **Actions:** Copy path + JSON

#### `renderGenericCall(ev, inp, idx)` (fallback)
- **CSS class:** `tc-wrap`
- **Header icons:** 🔧 with tool name + first 2 key=value args (or `_raw` preview)
- **Metadata:** all input key/value pairs
- **Actions:** JSON only

### Shared Helpers

| Helper | Purpose |
|---|---|
| `parseCallInput(ev)` | Parse `ev.input` (string JSON → object) |
| `countEditLines(edits)` | Returns `{ adds, rems, blocks }` from edit array |
| `formatContentSize(content)` | Formats byte size (e.g., "1.2 KB") |
| `previewTask(task, maxChars)` | First line of task, truncated |
| `shortModel(model)` | Strips provider prefix (e.g., `deepseek/deepseek-v4-pro` → `deepseek-v4-pro`) |
| `formatPlan(inp)` | Returns `{ total, done, inProg, pending, label }` |
| `buildTcBody(metaRows, actionsHtml)` | Builds `.tc-body` with grid metadata + action buttons |
| `tcJsonBtn(idx)` | Returns JSON viewer button |
| `tcCopyBtn(text)` | Returns copy button with data-copy attribute |

---

## Tool Result Rendering: `renderToolResult(ev, idx, expanded)`

**Location:** Section 23, lines ~2770–2795

```js
function renderToolResult(ev, idx, expanded) {
  // 1. Extract result string
  let resultStr = /* JSON.stringify or raw string */;
  const trimmed = resultStr.trim();

  // 2. Skip trivial results
  if (!trimmed || /^(ok|success|done|true|false|null|undefined)$/i.test(trimmed))
    return '';  // Renders nothing

  // 3. Parse envelope
  const parsed = parseToolResult(resultStr);

  // 4. Dispatch to per-tool header
  switch (ev.toolName) {
    case 'exec':     return renderExecHeader(ev, parsed, t, idx, expanded);
    case 'read':     return renderReadHeader(ev, parsed, t, idx, expanded);
    case 'edit':     return renderEditHeader(ev, parsed, t, idx, expanded);
    case 'write':    return renderWriteHeader(ev, parsed, t, idx, expanded);
    case 'process':  return renderProcessHeader(ev, parsed, t, idx, expanded);
    case 'memory_search': return renderMemorySearchHeader(ev, parsed, t, idx, expanded);
    case 'update_plan':   return renderUpdatePlanHeader(ev, parsed, t, idx, expanded);
    default:         return renderGenericHeader(ev, parsed, t, idx, expanded);
  }
}
```

**Important:** The renderer does NOT read `ev.input`. It looks up tool input by scanning `sessionEvents` backwards for the matching `tool_start` event with the same `toolCallId`.

### Trivial Result Skipping

Results matching `/^(ok|success|done|true|false|null|undefined)$/i` are skipped entirely. Note: this regex does NOT anchor word boundaries, so e.g. `"done."` would also match due to loose alternation.

### Per-Tool Result Header Renderers

All produce a **`.tr-wrap`** container with:
- **`.tr-header`** — clickable bar with `↳ toolname` tag, detail text, time
- **`.tr-body`** — hidden by default, shown when `.tr-expanded` is present
- Clicking header → `toggleToolResult(el, idx)` toggles `.tr-expanded`

#### `renderExecHeader(ev, parsed, t, idx, expanded)`
- **Looks up** matching `tool_start` by `toolCallId` scan (up to 30 events back) to get `command`
- **Exit code tag:** `tr-tag ok` (exit 0) or `tr-tag err` (non-zero) with label (SIGINT, SIGKILL, etc.)
- **Detail line:** formatted duration + shortened CWD
- **Stderr detection:** If non-zero exit OR `ev.isError` → `tr-stderr` class (red border) + "⚠ stderr" warning
- **Body:** command line, output in `tr-code`, output stats (lines + bytes), Copy + JSON buttons
- **Error styling:** `tr-code-error` class on error/non-zero output

#### `renderReadHeader(ev, parsed, t, idx, expanded)`
- **Looks up** matching `tool_start` by `toolCallId` (up to 10 events) for `filePath`
- **File viewer link:** clickable `📄 .../path` with `viewFile()` call
- **Line count:** parsed from result text split
- **Body:** code block (no max-height limit) + Copy + JSON buttons

#### `renderEditHeader(ev, parsed, t, idx, expanded)`
- **Looks up** matching `tool_start` for `filePath`
- **Error detection:** `ev.isError`, `parsed.isError`, error in details, or text starts with Error/Failed/✖/⚠
- **Header:** OK/ERROR tag + file link + truncated detail (120 chars)
- **On error:** Red error box with "✖ Edit Failed", error text, file path
- **On success (patch present):** Unified diff via `renderUnifiedDiff()` — single-column, line-by-line: removed lines in red, added lines in green, context lines in default text color, hunk headers as divider rows.
- **On success (edits, no patch):** Fallback to `.mem-card` cards (old ↓ red, new ↑ green, max 5 lines prev each)
- **On success (diff, no patch/edits):** Fallback to `renderDiff()` unified diff
- **Actions:** Copy + JSON

##### Unified diff helper

**`renderUnifiedDiff(patchText, filePath)`** — Simple single-column line-by-line renderer:
- `.udiff` → container (bordered, scrollable at 60vh, monospace)
- `.udiff-file` → file path bar (optional, shown when filePath provided)
- `.udiff-hunk` → hunk header row (info-colored, dark background)
- `.udiff-rem` → removed lines (red background + red text)
- `.udiff-add` → added lines (green background + green text)
- `.udiff-ctx` → context lines (default text color)
- Skips git diff boilerplate (`diff --git`, `index`, `---`, `+++`) and `\ No newline` markers

#### `renderWriteHeader(ev, parsed, t, idx, expanded)`
- **Looks up** matching `tool_start` for `filePath`
- **Header:** ✅ tag + file link (or text detail)
- **No body** (compact, no expand)
- File path shortened: `/home/ju/` → `~/`, then `.../filename`

#### `renderProcessHeader(ev, parsed, t, idx, expanded)`
- **Status extraction:** `d.status` with emoji (🟢 running / 🔴 killed / ✅ completed)
- **Detail:** status emoji + name + sessionId + exit code
- **Body:** `renderToolBody()` (code block + Copy + JSON)

#### `renderMemorySearchHeader(ev, parsed, t, idx, expanded)`
- **Results:** up to 5 result cards, each with path, score badge (percentage), excerpt (200 chars)
- **Header:** `🔍 N results`
- **Body:** memory cards + "No results" fallback + Copy + JSON

#### `renderUpdatePlanHeader(ev, parsed, t, idx, expanded)`
- **Plan summary:** `✅ N/M steps · 🔄 X in progress`
- **Body:** All plan steps with icons (✅/🔄/⬜) + text + Copy + JSON

#### `renderGenericHeader(ev, parsed, t, idx, expanded)` (fallback)
- **Header:** `↳ toolname` + optional "✖ error"
- **Body:** `renderToolBody()` (code block + Copy + JSON)

### Shared `renderToolBody(ev, parsed, idx)`

Universal fallback body renderer:
- Renders `parsed.text` as a code block
- Adds Copy + JSON action buttons
- Used by process, generic, and other simple tools

### Tool Result Envelope Parser: `parseToolResult(resultStr)`

**Location:** Section 13, lines ~1850–1870

```js
function parseToolResult(resultStr) {
  try {
    const obj = JSON.parse(resultStr);
    if (obj && typeof obj === 'object' && Array.isArray(obj.content)) {
      const text = obj.content
        .filter(c => c.type === 'text')
        .map(c => c.text)
        .join('\n');
      return {
        text: text || '',
        details: obj.details || null,
        isEnvelope: true,
        isError: !!obj.isError
      };
    }
    return { text: String(resultStr), details: null, isEnvelope: false, isError: false };
  } catch {
    return { text: String(resultStr), details: null, isEnvelope: false, isError: false };
  }
}
```

Recognized envelope format:
```json
{
  "content": [{ "type": "text", "text": "..." }],
  "details": { "exitCode": 0, "durationMs": 1234, "cwd": "/home/ju/project", ... },
  "isError": false
}
```

---

## `renderMarkdown(text)` — 12-Phase Pipeline

**Location:** Section 12, lines ~1783–1848

All `assistant_text` events are rendered through this pure-JS markdown-to-HTML converter (no external library).

```js
function renderMarkdown(text) {
  let html = escHtml(text);
  // Phase 1:  Fenced code blocks → \x00CODEn\x00 placeholders
  // Phase 2:  ATX headers (#### → h4, ### → h3, ## → h2, # → h1)
  // Phase 3:  Horizontal rules (---, ***, ___ → <hr>)
  // Phase 4:  Blockquotes (&gt; text → <blockquote>)
  // Phase 5:  Bold (**text**) + Italic (*text*)
  // Phase 6:  Inline code (`code` → <code>)
  // Phase 7:  Links ([text](url) → <a>)
  // Phase 8:  Images (![alt](url) → <img>)
  // Phase 9:  Unordered lists (* / - items → <li> → <ul>)
  // Phase 10: Ordered lists (1. items → <li> → <ol>)
  // Phase 11: Restore code blocks from \x00CODEn\x00
  // Phase 12: Wrap remaining lines in <p> tags
  return html;
}
```

### CSS for Markdown Output

All markdown content is wrapped in `<div class="md-content">`. Styled with:

| Element | Style |
|---|---|
| `p` | `margin: 0 0 8px` |
| `strong` | `color: #fff; font-weight: 700` |
| `em` | `font-style: italic; color: #d4d4d8` |
| `code` (inline) | `background: #1e2130; border; color: #f59e0b` |
| `pre code` | `no background; color: var(--text); line-height: 1.5` |
| `h1`–`h4` | Sized 18px→12px, bold, h1 has bottom border |
| `ul`, `ol` | `padding-left: 20px; margin: 4px 0 8px` |
| `blockquote` | `border-left: 3px solid var(--accent); muted color` |
| `a` | `color: var(--info); underline` |
| `hr` | `border-top: 1px solid var(--border)` |
| `table`, `th`, `td` | Borders, th background #1e2130, font-size 11px |
| `img` | `max-width: 100%; border-radius: 4px` |

---

## `highlightCode(text, lang)` — Syntax Highlighting

**Location:** Section 16, lines ~1910–1925

Simple regex-based highlighter that wraps tokens in `<span class="syn-*">`:

```js
function highlightCode(text, lang) {
  let html = escHtml(text);
  // Shell/Python comments:  # comment → syn-cmt
  html = html.replace(/(^|\n)(\s*)(#[^\n]*)/g, ...);
  // JS/C comments: // comment → syn-cmt
  html = html.replace(/(\/\/[^\n]*)/g, ...);
  // Strings: "..." and '...' → syn-str
  html = html.replace(/("(?:[^"\\]|\\.)*")/g, ...);
  html = html.replace(/('(?:[^'\\]|\\.)*')/g, ...);
  // Numbers: → syn-num
  html = html.replace(/\b(\d+\.?\d*)\b/g, ...);
  // Keywords (JS, Python, Bash): → syn-kw
  html = html.replace(/\b(const|let|var|function|return|if|else|...)\b/g, ...);
  return html;
}
```

Keyword list: `const, let, var, function, return, if, else, for, while, do, switch, case, break, continue, import, export, from, require, class, extends, new, this, try, catch, finally, throw, async, await, def, class, import, from, elif, yield, with, as, in, not, and, or, True, False, None, echo, export, local, source, exit, then, fi, done, esac`

CSS classes: `.syn-kw` (#c084fc purple), `.syn-str` (#4ade80 green), `.syn-cmt` (#71717a gray italic), `.syn-num` (#fbbf24 yellow)

---

## `renderDiff(diffText)` and `renderCodeBlock(text, lang, lineNumbers)`

**Location:** Section 17, lines ~1927–1955

### `renderDiff(diffText)`
- Lines starting with `@@` → `<span class="diff-hdr">` (info color)
- Lines starting with `+` → `<span class="diff-add">` (green background)
- Lines starting with `-` → `<span class="diff-rem">` (red background)
- Other lines → escHtml

### `renderCodeBlock(text, lang, lineNumbers)`
- Auto-enables line numbers for files > 20 lines
- Line numbers rendered via CSS counters (`.with-ln` class)
- Optional `lang` parameter passed to `highlightCode()`
- Container class: `tr-code` (max-height: 60vh, scrollable)

---

## Other `renderEvent()` Branches

### `thinking` Events
- **Wraps**: `msg-thinking` card (border-left: #a855f7)
- **Badge**: `💭` (purple background)
- **Truncation**: text capped at 2000 characters; if clipped, adds `... [truncated]` and `.clipped` class
- **Styling**: `color: var(--muted)` for subdued appearance

### `user_text` Events
- **Wraps**: `msg-user` card (border-left: var(--user) green)
- **Badge**: `👤 USER` (green background)
- **Pending state**: `.pending` class (opacity 0.6, 🕐 indicator)
- **Delivered state**: `.delivered` class (opacity 1, ✅ indicator)
- **No truncation** — full text always rendered
- **Text rendered via `escHtml()`** — NOT markdown

### `loading` Events (placeholder)
- **Wraps**: `msg-loading loading` card (border-left: var(--accent), pulsing animation)
- **Badge**: `⏳ WAITING` (muted gray)
- **Content**: `"Waiting for response..."` in italic muted text
- **Only created locally**, never from server

### `run_start` Events
- **gateway-injected souls**: Renders as `<div class="session-divider">` with `── ◈ SESSION START ◈ ──` text
- **Real run_start**: Badge `▶`, separate `Σ totalTokens` badge, model name, metadata line:
  - `in: N | out: N | ctx: N | $X.XXXX | seq: N`
  - If `ev.thinking` present (legacy): renders "💭 Thinking:" block with pre-wrap text

### `run_end` Events
- Renders as compact `■` card with stop reason and token metadata line
- Shown in the `all` filter; excluded from `llm`, `tool`, and `error` filters

### `run_error` Events
- **Wraps**: `msg-run-error` card (border-left: var(--error))
- **Badge**: `✖ ERROR` (red background)
- **Content**: error message in red text via `escHtml()`

---

## Compact Mode: `renderCompactRow(ev, idx, clickable)`

**Location:** Section 24, lines ~2817–2893

One-line preview rows used when `isExpanded(ev)` returns `false`. Renders emoji-tagged single-line summaries:

| Event Type | Emoji Tag | Content | Truncation |
|---|---|---|---|
| `assistant_text` | `💬` (blue bg) | Newlines→` ⏎ `, preview | 250 chars |
| `user_text` | `👤` (green bg) | Newlines→` ⏎ `, preview | 200 chars |
| `run_error` | `✖` (red bg) | Error message in red | 250 chars |
| `run_start` | `▶` (info bg) | Model + token stats | Unlimited (one line) |
| `thinking` | `💭` (purple bg) | Newlines→spaces | **No truncation** (white-space: nowrap) |

Each compact row has:
- Left color strip via CSS classes (`.compact-user`, `.compact-assistant`, etc.)
- Click to expand: `expandCompactRow(el, idx)` replaces the row with full render

### `expandCompactRow(el, idx)`
- Looks up event by index in `sessionEvents`
- Calls `renderEvent(ev, idx, true)` with `forceExpand=true`
- Replaces the compact row DOM element with the full HTML
- Falls back to dimming the row if event data is unavailable

---

## Expand/Collapse System

### State: `_expandedItems` Set
- **Default:** `new Set(['user', 'response'])` — user messages and responses always expanded
- **Stored in:** `localStorage` under `deepclaw-ui-prefs.expandedItems`
- **Keys:** Tool names (`'exec'`, `'read'`, etc.) + message types (`'thinking'`, `'user'`, `'response'`)

### `isExpanded(ev)`
```js
function isExpanded(ev) {
  if (ev.type === 'tool_result' && ev.toolName === 'update_plan') return false;
  if (ev.type === 'tool_start' || ev.type === 'tool_result')
    return _expandedItems.has(ev.toolName);
  if (ev.type === 'thinking') return _expandedItems.has('thinking');
  if (ev.type === 'user_text') return _expandedItems.has('user');
  if (ev.type === 'assistant_text') return _expandedItems.has('response');
  return true; // run_error, loading, run_end, gateway-injected
}
```

**Special case:** `update_plan` tool results are NEVER expanded (always compact).

### Expand Menu UI
- **Button:** `#expand-btn` — shows "🔽 Expand (N)" when items active
- **Menu:** `#expand-menu` dropdown with checkbox items
- **Sections:** "Messages" (user, response, thinking) + "Tools" (dynamic from session events)
- **Toggle:** `toggleExpandItem(key)` adds/removes key from `_expandedItems`, saves to localStorage, triggers full re-render

### Tool Result Toggle
- Clicking a `.tr-header` calls `toggleToolResult(el, idx)` → toggles `.tr-expanded` on the `.tr-wrap`
- Independent from the `_expandedItems` system — programmatic expansion vs user click expansion

---

## Scroll Behavior

### Variables
- `userScrolledUp: boolean` — true when user has scrolled away from bottom
- `pendingNewMessages: number` — count of new messages received while scrolled up
- `_programmaticScroll: boolean` — prevents scroll event handler from triggering during programmatic scroll

### Detection
```js
msgsEl.addEventListener('scroll', () => {
  if (_programmaticScroll) return;
  const atBottom = msgsEl.scrollHeight - msgsEl.scrollTop - msgsEl.clientHeight < 80;
  // 80px threshold from bottom
  if (atBottom) {
    userScrolledUp = false;
    pendingNewMessages = 0;
    hideNewMsgButton();
  } else {
    userScrolledUp = true;
  }
});
```

### Auto-scroll to Bottom
```js
function smoothScrollToBottom(msgsEl) {
  // rAF-batched, uses scrollTo({ behavior: 'instant' })
  // Sets _programmaticScroll = true during scroll
}
```

Called automatically on new events when `!userScrolledUp`.

### "↓ New Messages" Button
- **Element:** `#new-msg-btn` (fixed position at bottom of messages area)
- **Shown when:** new events arrive while `userScrolledUp === true`
- **Text:** `"↓ N new messages"` or `"↓ New messages"`
- **Click:** calls `scrollToBottom(true)`, clears `userScrolledUp` and `pendingNewMessages`

---

## `showSessionContent(sess)` — Content Rendering Orchestrator

**Location:** Section 10, lines ~1626–1750

### Overview
The central function that:
1. Updates the content title bar (session key + total tokens + model badge)
2. Applies filter via `getFilteredEvents(sess)`
3. Marks `assistant_text` events as `isFinal` / `isIntermediate`
4. Computes `cumTotal` (cumulative total tokens) for each event
5. Handles lazy-load session boundary slicing
6. Decides compact vs expanded rendering per event
7. Manages incremental append vs full rebuild
8. Handles scroll tracking

### Rendering Decision Matrix

| Event Type | Condition | Action |
|---|---|---|
| `tool_start` | `isExpanded(ev)` | Full `renderEvent()` |
| `tool_start` | not expanded | `renderEvent()` (always full for tool calls) |
| `tool_result` | `isExpanded(ev)` | Full `renderEvent()` |
| `tool_result` | not expanded | `renderEvent()` |
| `run_start` (gateway-injected) | always | Full `renderEvent()` → session divider |
| `run_start` (real) | always | `renderCompactRow()` |
| `assistant_text` (isIntermediate) | always | **skipped** |
| `assistant_text` (tool-call-only stub) | always | **skipped** |
| `assistant_text` | `isExpanded(ev)` | Full `renderEvent()` |
| `assistant_text` | not expanded | `renderCompactRow()` |
| `thinking` | `isExpanded(ev)` | Full `renderEvent()` |
| `thinking` | not expanded | `renderCompactRow()` |
| `user_text` | `isExpanded(ev)` | Full `renderEvent()` |
| `user_text` | not expanded | `renderCompactRow()` |
| `run_error` | always | Full `renderEvent()` |
| `loading` | always | Full `renderEvent()` |

### Intermediate `assistant_text` Skipping
- Events marked `isIntermediate` are tool-call-interrupted responses
- Events matching regex `/^\s*(\[tool:[^\]]*\]\s*)+$/` (tool-call-only stubs) are also skipped

### Incremental Rendering
- `sess._renderedCount` tracks how many events have been rendered
- If `newCount > prevCount`: **incremental append** via `DocumentFragment`
- If `newCount < prevCount` or `filterChanged` or `prevCount === 0`: **full rebuild**
- On full rebuild, scroll position is proportionally preserved

---

## HTML Escaping

```js
function escHtml(s) {
  return String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;')
    .replace(/>/g, '&gt;').replace(/"/g, '&quot;');
}

function escAttr(s) {
  return String(s).replace(/"/g, '&quot;').replace(/'/g, '&#39;');
}
```

- `escHtml()` — used for all text content injection
- `escAttr()` — used for attribute values (title, data-* attributes, onclick handlers)

---

## Format Helpers Reference

| Function | Purpose | Example Output |
|---|---|---|
| `formatBytes(n)` | Byte size formatting | `"1.2 KB"`, `"500 B"` |
| `formatDuration(ms)` | Duration formatting | `"2.5s"`, `"1m 30s"`, `"500ms"` |
| `shortCwd(cwd)` | Path shortening | `"~/project/.../src"`, `"/etc/.../nginx"` |
| `exitLabel(code)` | Exit code labels | `"ok"`, `"SIGKILL"`, `"SIGTERM"` |
| `formatOutputStats(text)` | Output stats | `"42 lines · 1.2 KB"` |

---

## File Viewing & Download: `viewFile()` / `downloadFile()`

**Location:** Section 20, lines ~2352–2382

Both call `POST /api/files/share` with `{ filePath }`:
- `viewFile(path)` → opens `data.viewUrl` in new tab
- `downloadFile(path)` → opens `data.url` in new tab

Used by per-tool renderers: read, edit, write call/result headers have clickable file links and 👁 viewer buttons.

---

## Data Flow: Event Object Shapes

### `tool_start` event
```js
{
  type: 'tool_start',
  runId: string,
  toolName: string,        // e.g. 'exec', 'read', 'write', 'edit', 'memory_search'
  input: object | string,  // parsed from gateway or raw JSON string
  toolCallId: string,
  ts: Date,
  cumTotal: number         // added by showSessionContent()
}
```

### `tool_result` event
```js
{
  type: 'tool_result',
  runId: string,
  toolName: string,
  result: string,          // always stringified by handler
  isError: boolean,
  toolCallId: string,
  ts: Date,
  // NOTE: NO 'input' field. Renderers look up tool_start by toolCallId.
}
```

### `assistant_text` event
```js
{
  type: 'assistant_text',
  runId: string,
  text: string,
  ts: Date,
  isFinal: boolean,        // set by showSessionContent() — last response before run_end
  isIntermediate: boolean, // set by showSessionContent() — intermediate (has tool calls after)
  hasToolCalls: boolean,   // set by showSessionContent()
  cumTotal: number         // added by showSessionContent()
}
```

### `user_text` event
```js
{
  type: 'user_text',
  runId: string,
  text: string,
  ts: Date,
  source: 'local' | 'canonical',  // local = browser-injected, canonical = server
  pending: boolean,                // optimistic injection (not yet confirmed)
  delivered: boolean,              // confirmed by server
  cumTotal: number
}
```

### `thinking` event
```js
{
  type: 'thinking',
  runId: string,
  text: string,
  ts: Date,
  cumTotal: number
}
```

### `run_start` event
```js
{
  type: 'run_start',
  runId: string,
  model: string,
  model: 'gateway-injected',  // special marker for session boundaries
  inputTokens: number,
  outputTokens: number,
  totalTokens: number,
  contextTokens: number,
  estimatedCost: number,
  messageSeq: number,
  thinking: string,          // legacy backwards compat (pre-response reasoning)
  ts: Date,
  cumTotal: number
}
```

### `run_end` event
```js
{
  type: 'run_end',
  runId: string,
  stopReason: string,
  inputTokens: number,
  outputTokens: number,
  totalTokens: number,
  contextTokens: number,
  estimatedCost: number,
  ts: Date
}
```

### `run_error` event
```js
{
  type: 'run_error',
  runId: string,
  error: string,
  ts: Date
}
```

### `loading` event (frontend-only)
```js
{
  type: 'loading',
  runId: string,      // matches the local user_text runId
  ts: Date,
  source: 'local'
}
```
