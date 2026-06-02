# Event Types Reference

This document describes each event type rendered by the frontend in `index.html`, including exact field shapes, rendering behavior, and how events flow through the system.

---

## Event Flow Overview

Events arrive at the frontend through two paths:

1. **`event.added`** — The primary real-time ingestion path. One event appended per call. Handles streaming merges, dedup, pending state transitions.
2. **`session.tool` (legacy)** — Older gateway path that dispatches by `stream`/`phase`. Still handled but secondary to `event.added`.

Additional paths:
- **`session.sync`** — Full session load on connect (replaces events array)
- **`sessions.history`** — Historical message batch (appends `user_text`/`assistant_text`)
- **`chat`** — Generates a `run_end` event

Events are stored in `sess.events[]` (per-session array). During rendering, `showSessionContent()` adds `cumTotal` (the session's total tokens) as an artificial display field on each event — **this field does NOT exist on stored events.**

---

## 1. `user_text`

User input message.

### Fields

| Field | Type | Description |
|-------|------|-------------|
| `type` | string | `"user_text"` |
| `runId` | string | Unique run identifier (e.g. `"local-1717800000000"`) |
| `text` | string | User message (no truncation) |
| `ts` | Date | Timestamp |
| `source` | string | `"local"` (this tab sent it) or `"canonical"` (server-originated) |
| `pending` | boolean | True while waiting for server confirmation (optimistic injection) |
| `delivered` | boolean | True after server confirmation received |

### Sample Data

```json
{
  "type": "user_text",
  "runId": "local-1717800000000",
  "text": "What's the weather like in Tokyo today?",
  "ts": "2025-11-01T12:00:00.000Z",
  "source": "local",
  "pending": false,
  "delivered": true
}
```

### Rendering

- Badge: `👤 USER` (green)
- **Full text shown** (no truncation), `escHtml()`-escaped (plain text, not markdown)
- CSS classes: `msg-user`, `msg-user.pending` (dimmed), `msg-user.delivered` (normal)
- In compact mode: preview of first 200 chars with `👤` tag

---

## 2. `assistant_text`

Model response text. The primary content display type.

### Fields

| Field | Type | Description |
|-------|------|-------------|
| `type` | string | `"assistant_text"` |
| `runId` | string | Unique run identifier |
| `text` | string | Response content (markdown) |
| `ts` | Date | Timestamp |
| `isFinal` | boolean | Set by `showSessionContent()` — the LAST assistant_text in a completed run |
| `isIntermediate` | boolean | Set by `showSessionContent()` — earlier assistant_text in a multi-turn run |
| `hasToolCalls` | boolean | May be set externally to mark intermediate-with-tool-calls |

### Sample Data

```json
{
  "type": "assistant_text",
  "runId": "abc123",
  "text": "The weather in San Francisco is currently **62°F** with partly cloudy skies.",
  "ts": "2025-11-01T12:00:00.500Z",
  "isFinal": true,
  "isIntermediate": false
}
```

### Rendering

- Badge: `🤖💬` (indigo/blue)
- **Full text rendered as Markdown** — `renderMarkdown()` transforms text through a 12-phase parser: fenced code blocks → headers → horizontal rules → blockquotes → bold/italic → inline code → links → images → unordered lists → ordered lists → code restore → paragraph wrapping
- **No truncation** — large responses render in full
- CSS class: `md-content` wrapping the rendered HTML
- Intermediate responses (with `hasToolCalls` or marked `isIntermediate`) are **skipped** in rendering
- Tool-call-only stubs (matching `/^\s*(\[tool:[^\]]*]\s*)+$/`) are also skipped

---

## 3. `thinking`

Internal model reasoning. Shown grayed out.

### Fields

| Field | Type | Description |
|-------|------|-------------|
| `type` | string | `"thinking"` |
| `runId` | string | Unique run identifier |
| `text` | string | Reasoning content |
| `ts` | Date | Timestamp |

### Sample Data

```json
{
  "type": "thinking",
  "text": "The user is asking about the weather. I should check the location from the user context, then call the weather API.",
  "ts": "2025-11-01T12:00:00.200Z"
}
```

### Rendering (Expanded)

- Badge: `💭` (purple)
- **Truncated at 2000 chars** (with `... [truncated]` indicator and `.clipped` class)
- Muted styling (grayed text via `color: var(--muted)`)
- **This is the primary thinking display mechanism** — thinking was previously embedded in `run_start`
- Covers ALL thinking phases: pre-response reasoning AND thinking during tool calls
- During streaming from `event.added`, thinking deltas are appended to a single event (merged by `runId`)

### Rendering (Compact)

- One-liner preview with `💭` tag
- **Full text included in HTML** (no truncation guard applied, `white-space: nowrap` just prevents wrapping on screen)
- ⚠️ Compact thinking rows can be enormous with no length limit

---

## 4. `tool_start`

A tool execution has begun.

### Fields

| Field | Type | Description |
|-------|------|-------------|
| `type` | string | `"tool_start"` |
| `runId` | string | Unique run identifier |
| `toolName` | string | Name of the tool being called |
| `input` | object \| string | Tool input/arguments (parsed JSON or raw string) |
| `toolCallId` | string | Call ID for tracking (used to match with `tool_result`) |
| `ts` | Date | Timestamp |

### Rendering

Renders as a **per-tool call card** (`.tc-wrap`), not a generic badge+JSON dump:

| Tool | Renderer | Card Content |
|------|----------|-------------|
| `exec` | `renderExecCall` | Command line, workdir, background/timeout/pty/elevated flags |
| `read` | `renderReadCall` | File path, offset/limit, copy/view actions |
| `edit` | `renderEditCall` | File path, edit block counts (-old/+new lines per block) |
| `write` | `renderWriteCall` | File path, content size, content preview |
| `update_plan` | `renderPlanCall` | Plan steps with status icons, explanation |
| `sessions_spawn` | `renderSpawnCall` | Task preview, model, cwd, context, timeout |
| `sessions_yield` | `renderYieldCall` | Message preview |
| `process` | `renderProcessCall` | Action, sessionId, timeout/limit/data |
| `memory_search` | `renderMemSearchCall` | Query, maxResults, minScore, corpus |
| `memory_get` | `renderMemGetCall` | Path, from/lines range, corpus |
| *(any other)* | `renderGenericCall` | All input keys as a metadata grid |

Each card has a `.tc-header` (click to expand), `.tc-body` with metadata grid (`.tc-meta`) and action buttons (`.tc-actions`: Copy + JSON viewer).

In compact mode: expanded only if `_expandedItems` includes the tool name. Otherwise shows a compact `▶ model | Σ tokens | ...` row.

---

## 5. `tool_result`

A tool has finished executing.

### Fields

| Field | Type | Description |
|-------|------|-------------|
| `type` | string | `"tool_result"` |
| `runId` | string | Unique run identifier |
| `toolName` | string | Name of the tool |
| `result` | string | Tool output (always stringified by handler) |
| `isError` | boolean | Error flag |
| `toolCallId` | string | Call ID (used to look up the matching `tool_start` for context) |
| `ts` | Date | Timestamp |

> **Note:** The `input` field is NOT read by the renderers. Instead, renderers scan the session's events backwards to find the matching `tool_start` by `toolCallId` to extract file paths, commands, and other context.

### Rendering

Renders as a **per-tool expandable header** (`.tr-wrap`), not a flat text label:

| Tool | Renderer | Header Content |
|------|----------|---------------|
| `exec` | `renderExecHeader` | Exit code tag (ok/err), duration, cwd, command line, full output, copy/JSON buttons |
| `read` | `renderReadHeader` | File path (clickable to view), line count, full content with syntax highlighting |
| `edit` | `renderEditHeader` | Success/error tag, file path, edit blocks preview (-old/+new), diff block, copy/JSON buttons |
| `write` | `renderWriteHeader` | File path (clickable), ✅ confirmation |
| `process` | `renderProcessHeader` | Status emoji, session name, exit code, full body |
| `memory_search` | `renderMemorySearchHeader` | Result count, memory cards with path/score/excerpt |
| `update_plan` | `renderUpdatePlanHeader` | Completed/total steps, plan steps with status icons |
| *(any other)* | `renderGenericHeader` | Tool name, error indicator, full body |

**Trivial results are hidden:** Results matching `/^(ok|success|done|true|false|null|undefined)$/i` (tested against trimmed string) are silently skipped. Note: this is a regex match that may match substrings (e.g. "done." would be skipped).

**Code blocks** use `max-height: 60vh` (not 200px as previously documented).

**Streaming merge:** During `event.added` streaming, `tool_result` text is appended to the existing event (matched by `toolCallId` + `runId`).

---

## 6. `run_start`

An LLM run has started.

### Fields

| Field | Type | Description |
|-------|------|-------------|
| `type` | string | `"run_start"` |
| `runId` | string | Unique run identifier |
| `model` | string | Model name (may be `"gateway-injected"` for session boundary markers) |
| `inputTokens` | number | *(from server event.added)* Input token count |
| `outputTokens` | number | *(from server event.added)* Output token count |
| `totalTokens` | number | *(from server event.added)* Total tokens |
| `contextTokens` | number | *(from server event.added)* Context size |
| `estimatedCost` | number | *(from server event.added)* Estimated cost in USD |
| `thinking` | string | *(optional, legacy)* Initial thinking (rendered as "💭 Thinking:" block) |
| `messageSeq` | number | *(optional)* Sequence number |
| `ts` | Date | Timestamp |

> **Note:** `inputTokens`, `outputTokens`, `totalTokens`, `contextTokens`, `estimatedCost`, `thinking`, and `messageSeq` are provided by the server via `event.added`. The frontend's `session.tool` lifecycle handler only creates `model` and `runId`.

### Rendering (Normal)

- Badge: `▶` (blue, just a play icon)
- **Token badge:** `Σ totalTokens` (separate accent-colored badge, not inline metadata)
- Model name displayed next to badge
- Metadata line: `in: X | out: Y | ctx: K | $X.XXXX | seq: N`
- Legacy thinking: if `ev.thinking` exists, renders "💭 Thinking:" in a styled block

### Rendering (Session Dividers)

When `model === 'gateway-injected'`, renders as a session divider:
`── ◈ SESSION START ◈ ──` with timestamp.

These dividers are **always included** in filtered views (bypass the filter), are excluded from compact mode, and are used by the lazy-load system to display only N most recent session boundaries.

---

## 7. `run_end`

An LLM run has finished.

### Fields

| Field | Type | Description |
|-------|------|-------------|
| `type` | string | `"run_end"` |
| `runId` | string | Unique run identifier |
| `stopReason` | string | Why it stopped (e.g. "stop", "completed") |
| `inputTokens` | number | *(from server)* Input token count |
| `outputTokens` | number | *(from server)* Output token count |
| `totalTokens` | number | *(from server)* Total tokens |
| `contextTokens` | number | *(from server)* Context size |
| `estimatedCost` | number | *(from server)* Estimated cost in USD |
| `ts` | Date | Timestamp |

### Sample Data

```json
{
  "type": "run_end",
  "runId": "abc123",
  "stopReason": "stop",
  "inputTokens": 1500,
  "outputTokens": 234,
  "totalTokens": 1734,
  "contextTokens": 200000,
  "estimatedCost": 0.0031,
  "ts": "2025-11-01T12:00:01.000Z"
}
```

### Rendering

- Renders as a compact `■` badge with stop reason and token metadata line
- Shown in the `all` filter; excluded from `llm`, `tool`, and `error` filters
- `run_end` events are stored in the event array and visible in the JSON viewer
- When `run_end` arrives via `event.added`, it: triggers pending state cleanup, and marks the last `assistant_text` in the same run as `isFinal`

---

## 8. `run_error`

An LLM run encountered an error.

### Fields

| Field | Type | Description |
|-------|------|-------------|
| `type` | string | `"run_error"` |
| `runId` | string | Unique run identifier |
| `error` | string | Error message |
| `ts` | Date | Timestamp |

### Sample Data

```json
{
  "type": "run_error",
  "runId": "abc123",
  "error": "Rate limit exceeded: too many requests",
  "ts": "2025-11-01T12:00:01.000Z"
}
```

### Rendering

- Badge: `✖ ERROR` (red)
- Error message in red
- Timestamp
- In compact mode: one-liner with `✖` tag
- **Not included** in the `llm` filter (llm filter is: `run_start, thinking, assistant_text, user_text`)

---

## 9. `loading`

Optimistic placeholder shown while waiting for a response.

### Fields

| Field | Type | Description |
|-------|------|-------------|
| `type` | string | `"loading"` |
| `runId` | string | Matches the pending `user_text` runId |
| `ts` | Date | Timestamp |
| `source` | string | `"local"` |

### Rendering

- Badge: `⏳ WAITING`
- Message: "Waiting for response..."
- CSS class: `msg-loading loading`
- Injected 800ms after user sends a message
- Removed when first real response event arrives (`run_start`, `thinking`, `tool_start`, `assistant_text`, `run_error`)
- Also removed on 60s timeout or when `clearPendingState()` is called

### Sample Data

```json
{
  "type": "loading",
  "runId": "local-1717800000000",
  "ts": "2025-11-01T12:00:00.800Z",
  "source": "local"
}
```

---

## Summary Table

| Event Type | Badge | Key Fields | Truncation | Filter Inclusion |
|------------|-------|------------|------------|-----------------|
| `user_text` | 👤 USER | text, source, pending, delivered | **None** | all, llm |
| `assistant_text` | 🤖💬 | text (markdown), isFinal, isIntermediate | **None** (full markdown render) | all, llm |
| `thinking` | 💭 | text | 2000 chars (expanded), no limit (compact) | all, llm |
| `tool_start` | per-tool card | toolName, input, toolCallId | None | all, tool |
| `tool_result` | per-tool header | toolName, result, isError, toolCallId | trivial hidden; code max 60vh | all (not in tool filter) |
| `run_start` | ▶ | model, tokens, cost | — | all, llm |
| `session-divider` | ── ◈ SESSION START ◈ ── | model='gateway-injected' | — | **Always shown** (bypasses filters) |
| `run_end` | ■ | stopReason, tokens, cost | None | all |
| `run_error` | ✖ ERROR | error | None | all, error |
| `loading` | ⏳ WAITING | runId | — | all |

---

## Choosing What to Display

### For a minimalist view:
- Show: `user_text`, `assistant_text`, `thinking`, `tool_result`
- Also show `tool_start` for `image_generate`, `sessions_spawn`, `sessions_yield` (so prompt/task/message is readable)
- For `image_generate` `tool_result`, show only when `status: completed` (hide intermediate/running states)
- For `sessions_spawn` `tool_result`, show `childSessionKey` as clickable badge — clicking switches to that session in the sidebar
- For `sessions_yield` `tool_result`, hide entirely (no useful information)

### For debugging:
- Show all types (run_end is shown in the `all` filter)

### For metrics/analytics:
- Focus on: `run_start` (contains token counts)
- Or use the session sidebar which aggregates stats

### Filter buttons (actual behavior):

```javascript
// 'all':  everything
// 'llm':  run_start, thinking, assistant_text, user_text (NOT run_end)
// 'llm':  run_start, thinking, assistant_text, user_text
// 'tool': tool_start only (NOT tool_result)
// 'error': run_error only

// run_end is shown in 'all' filter, excluded from 'llm'/'tool'/'error'
// gateway-injected session dividers are ALWAYS included regardless of filter
```

---

## Tool Input Reference

Based on actual usage from session logs and renderer code. Each tool's full input structure:

### `read`

Read file contents.

```json
{
  "path": "/home/ju/test.txt",
  "offset": 870,
  "limit": 150
}
```

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `path` | string | yes | File path (relative or absolute) |
| `offset` | number | no | Line number to start reading (1-indexed) |
| `limit` | number | no | Maximum number of lines to read |

---

### `write`

Create or overwrite a file.

```json
{
  "path": "/home/ju/deepclaw-ui/docs/event-types-reference.md",
  "content": "# Event Types Reference\n\n..."
}
```

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `path` | string | yes | File path to write to |
| `content` | string | yes | File content |

---

### `edit`

Make precise edits to an existing file.

```json
{
  "path": "/home/ju/deepclaw-ui/index.html",
  "edits": [
    {
      "oldText": "</body>\n</html>",
      "newText": "<!-- JSON Viewer Modal -->..."
    }
  ]
}
```

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `path` | string | yes | File path to edit |
| `edits` | array | yes | Array of edit objects |

**Edit object:**
| Field | Type | Description |
|-------|------|-------------|
| `oldText` | string | Exact text to find and replace (must be unique in file) |
| `newText` | string | Replacement text |

---

### `exec`

Execute shell commands.

```json
{
  "command": "git status",
  "workdir": "/home/ju/deepclaw-ui",
  "background": true,
  "yieldMs": 3000,
  "timeout": 60
}
```

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `command` | string | yes | Shell command to execute |
| `workdir` | string | no | Working directory |
| `background` | boolean | no | Run in background immediately |
| `yieldMs` | number | no | Wait before backgrounding (default 10000ms) |
| `timeout` | number | no | Timeout in seconds |
| `pty` | boolean | no | Run in PTY (for interactive CLIs) |
| `elevated` | boolean | no | Run with elevated permissions |
| `env` | object | no | Environment variables |

---

### `process`

Manage background exec sessions.

```json
{
  "action": "log",
  "sessionId": "fast-sable",
  "limit": 10
}
```

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `action` | string | yes | Action: `list`, `poll`, `log`, `write`, `send-keys`, `submit`, `paste`, `kill` |
| `sessionId` | string | yes* | Session ID (required for actions other than list) |
| `data` | string | no | Data to write |
| `keys` | array | no | Key tokens to send |
| `text` | string | no | Text to paste |
| `limit` | number | no | Log lines to retrieve |
| `offset` | number | no | Log offset |
| `timeout` | number | no | Timeout in ms |

---

### `sessions_spawn`

Spawn a new agent session (subagent).

```json
{
  "task": "Rewrite the documentation for the websocket client",
  "taskName": "rewrite-docs",
  "model": "deepseek/deepseek-v4-pro",
  "cwd": "/home/ju/deepclaw-ui",
  "context": "fork"
}
```

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `task` | string | yes | Task description/prompt for the subagent |
| `taskName` | string | no | Named identifier for the task |
| `model` | string | no | Model override for this subagent |
| `cwd` | string | no | Working directory |
| `context` | string | no | Context mode: `"fork"` or omitted |
| `timeoutSeconds` | number | no | Timeout for the subagent |

---

### `sessions_yield`

Yield the current turn to wait for subagent results.

```json
{
  "message": "Waiting for subagent results"
}
```

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `message` | string | no | Status message to display while yielding |

---

### `memory_search`

Search memory files.

```json
{
  "query": "deepclaw-ui websocket implementation",
  "maxResults": 5,
  "minScore": 0.5,
  "corpus": "all"
}
```

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `query` | string | yes | Search query string |
| `maxResults` | number | no | Maximum number of results |
| `minScore` | number | no | Minimum relevance score (0-1) |
| `corpus` | string | no | Corpus to search: `"memory"`, `"wiki"`, `"all"`, `"sessions"` |

---

### `memory_get`

Retrieve a specific memory file by path.

```json
{
  "path": "/home/ju/.openclaw/workspace/deepui/MEMORY.md",
  "from": 100,
  "lines": 50
}
```

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `path` | string | yes | Memory file path |
| `from` | number | no | Starting line number |
| `lines` | number | no | Number of lines to retrieve |
| `corpus` | string | no | Corpus: `"memory"`, `"wiki"`, `"all"` |

---

### `update_plan`

Update a structured work plan (used in planning mode).

```json
{
  "plan": [
    { "step": "Read reference files", "status": "completed" },
    { "step": "Rewrite websocket-client.md", "status": "in_progress" },
    { "step": "Update event-types-reference.md", "status": "pending" }
  ],
  "explanation": "Starting documentation rewrite based on audit findings"
}
```

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `plan` | array | yes | Ordered list of plan steps |
| `explanation` | string | no | Optional note explaining the plan change |

**Plan step object:**
| Field | Type | Description |
|-------|------|-------------|
| `step` | string | Step description |
| `status` | string | One of: `"pending"`, `"in_progress"`, `"completed"` |

---

### `image_generate`

Create or edit images. Async tool — returns immediately with task ID, completion arrives via system event.

```json
{
  "action": "generate",
  "prompt": "Cinematic film still, 16:9 aspect ratio...",
  "size": "1792x1024",
  "outputFormat": "png",
  "filename": "cover"
}
```

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `action` | string | no | `"generate"` (default), `"status"` (check active task), `"list"` (enumerate providers) |
| `prompt` | string | yes* | Image generation prompt (*required for generate) |
| `image` | string | no | Single reference image path/URL (for edits) |
| `images` | array | no | Reference images (max 10) |
| `model` | string | no | Provider/model override |
| `filename` | string | no | Output filename hint |
| `size` | string | no | e.g. `"1024x1024"`, `"1792x1024"` |
| `aspectRatio` | string | no | e.g. `"16:9"`, `"1:1"` |
| `resolution` | string | no | `"1K"`, `"2K"`, `"4K"` |
| `quality` | string | no | `"low"`, `"medium"`, `"high"`, `"auto"` |
| `outputFormat` | string | no | `"png"`, `"jpeg"`, `"webp"` |
| `background` | string | no | `"transparent"`, `"opaque"`, `"auto"` |
| `count` | number | no | 1–4 images |
| `timeoutMs` | number | no | Provider timeout in ms |
| `openai` | object | no | `{ background, moderation, outputCompression, user }` |
| `fal` | object | no | `{ creativity: "raw"\|"low"\|"medium"\|"high" }` |

**Result shapes:**
- **generate (started):** `{ async: true, status: "started", taskId: "...", size, outputFormat }`
- **list:** `{ providers: [{ id, label, models, modes, configured }] }`
- **status:** `{ active: true, status: "running", provider, progressSummary }`

---

### `video_generate`

Create videos. Async, same pattern as `image_generate`.

```json
{
  "prompt": "A drone flyover of a futuristic city...",
  "durationSeconds": 5,
  "size": "1280x720"
}
```

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `action` | string | no | `"generate"` (default), `"status"`, `"list"` |
| `prompt` | string | yes* | Video prompt |
| `image` / `images` | string/array | no | Reference images |
| `video` / `videos` | string/array | no | Reference videos |
| `model` | string | no | Provider/model override |
| `filename` | string | no | Output filename hint |
| `size` | string | no | e.g. `"1280x720"`, `"1920x1080"` |
| `aspectRatio` | string | no | e.g. `"16:9"` |
| `resolution` | string | no | `"360P"`–`"1080P"`, `"4K"` |
| `durationSeconds` | number | no | Target seconds |
| `audio` | boolean | no | Generated audio toggle |
| `watermark` | boolean | no | Watermark toggle |
| `timeoutMs` | number | no | Provider timeout in ms |
| `providerOptions` | object | no | Provider-specific JSON options |

---

### `music_generate`

Create audio/music. Async, same pattern.

```json
{
  "prompt": "Upbeat electronic track with synth bass...",
  "lyrics": "We are the future...",
  "instrumental": false
}
```

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `action` | string | no | `"generate"` (default), `"status"`, `"list"` |
| `prompt` | string | no | Music style/genre prompt |
| `lyrics` | string | no | Exact sung lyrics |
| `instrumental` | boolean | no | Instrumental-only toggle |
| `image` / `images` | string/array | no | Reference images |
| `model` | string | no | Provider/model override |
| `durationSeconds` | number | no | Target seconds |
| `format` | string | no | `"mp3"`, `"wav"` |
| `filename` | string | no | Output filename hint |

---

### `message`

Send a message to a session, channel, or recipient.

```json
{
  "message": "Here's the report you asked for",
  "channel": "signal",
  "to": "+1234567890"
}
```

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `message` | string | yes | Message text |
| `channel` | string | no | Delivery channel |
| `to` | string | no | Recipient identifier |
| `filePath` | string | no | File attachment path |
| `sessionKey` | string | no | Target session key |

---

## Tool Result Types

Results vary by tool. Most results are envelopes parsed by `parseToolResult()`:

```json
{
  "content": [
    { "type": "text", "text": "file contents here..." }
  ],
  "details": {
    "durationMs": 1234,
    "cwd": "/home/ju/deepclaw-ui",
    "exitCode": 0,
    "diff": "...",
    "edits": [...],
    "results": [...]
  },
  "isError": false
}
```

**Envelope fields:**
- `content` — Array of content blocks (each with `type` and `text`)
- `details` — Tool-specific metadata (varies by tool)
- `isError` — Error flag

**Non-envelope results** are treated as plain text.

| Tool | Result Type | Description |
|------|-------------|-------------|
| `exec` | envelope | Command output, exit code, duration, cwd |
| `read` | string or envelope | File contents (rendered with syntax highlighting) |
| `write` | string | Success message with char count |
| `edit` | envelope | Diff, edit blocks, success/error |
| `process` | envelope | Status, exit code, session ID |
| `memory_search` | envelope | results[] array with path, score, excerpt |
| `update_plan` | envelope | plan[] array with step statuses |
| `image_generate` | envelope | Async: status, taskId, provider, size, format. Also handles list (providers) and status (progress) |
| `video_generate` | envelope | Async: same pattern as image_generate |
| `music_generate` | envelope | Async: same pattern as image_generate |
| `message` | envelope | Delivery status, channel, target |
| *(other)* | envelope or string | Generic rendering |

**Error results** start with `"Error:"` or have `isError: true` in the envelope — the UI flags these red.
