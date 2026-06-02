# Render Error Boundary — Resilience Against Unhandled Tool/Event Types

**Created:** 2026-06-02  
**Status:** Completed  
**Trigger:** Client halted on page load. Data files cleared → fixed.  
**Suspected root cause:** Unhandled exception in `renderEvent` → `showSessionContent` render pipeline aborts silently (no try-catch). One bad event poisons the whole UI render.

## Background

### What Happened

1. Ju was batch-generating 14 cover images using `image_generate` tool
2. Each generation also used `message` tool to send completion results
3. Dashboard client began halting on load (page freezes, nothing renders)
4. Clearing `data/` session files fixed the issue immediately
5. Data files themselves were structurally valid — no JSON corruption, no type anomalies

### Key Observation

The frontend's `renderToolCall` and `renderToolResult` switches handle only 10 tool names explicitly:

```javascript
// renderToolCall switch: exec, read, edit, write, update_plan, sessions_spawn, sessions_yield, process, memory_search, memory_get
// renderToolResult switch: exec, read, edit, write, process, memory_search, update_plan
```

`image_generate`, `message`, `video_generate`, `music_generate` all fall through to generic renderers. The generic path should work — it just displays key=value pairs — but these tools produce event shapes (async completions, `terminate:true`, file paths, Unicode surrogate pairs in message payloads) that haven't been exercised through the generic renderer before.

### The Vulnerability

`showSessionContent()` builds the entire session HTML by calling `renderEvent()` for each visible event. **There is zero error handling around these calls.** If any single `renderEvent()` call throws, `showSessionContent()` exits mid-build, the `msgsEl.innerHTML` is never set, and the UI appears dead — no error message, no partial content, just blank/broken.

```javascript
// Current code in showSessionContent (line ~1818):
rendered.forEach((ev, idx) => {
    const fullIdx = sliceFrom + idx;
    if (ev.type === 'tool_start' || ev.type === 'tool_result') {
        parts.push(renderEvent(ev, fullIdx, shouldExpand));  // ← no try-catch
    } else if (...) {
        parts.push(renderEvent(ev, fullIdx));                 // ← no try-catch
    }
    // ... etc
});
```

The same issue exists in the incremental append path (line ~1865-1890).

## Research Plan

### 1. Identify All Crash Vectors in `renderEvent` → Sub-Renderers

Trace every code path that `renderEvent` can take and identify where an unhandled exception could occur:

| Path | Function | Potential Failure |
|------|----------|-------------------|
| `assistant_text` | `renderMarkdown(text)` | Regex catastrophic backtracking on pathological input |
| `tool_start` | `renderToolCall()` → per-tool renderers → `parseCallInput()` | `JSON.parse` on malformed input (handled by catch) |
| `tool_result` | `renderToolResult()` → per-tool renderers → `parseToolResult()` | `JSON.parse` on malformed result (handled by catch) |
| `tool_result` | `renderEditHeader()` → `renderUnifiedDiff()` | Large diff processing, line splitting |
| `tool_result` | `renderToolBody()` → `renderCodeBlock()` → `highlightCode()` | Regex on large text blocks |
| All text events | `escHtml(s)` | `String(s).replace(...)` on `undefined`/`null` text (current code uses `ev.text \|\| ''` so should be safe) |
| Generic renderers | `renderGenericCall()`, `renderGenericHeader()` | Iterating `Object.keys(inp)` — `inp` from `parseCallInput` could be `null` if `ev.input` is `null` |

### 2. Investigate `image_generate` and `message` Event Shapes

Both tools produce events with fields the generic renderers may not expect:

**`image_generate` tool_result:**
```json
{
  "content": [{"type": "text", "text": "Background task started for image generation (...)"}],
  "details": {
    "async": true,
    "status": "started",
    "taskId": "...",
    "runId": "tool:image_generate:...",
    "terminate": true
  }
}
```

**`message` tool_start:**
```json
{
  "action": "send",
  "message": "🎨 **Title** — cover image ready.",
  "filePath": "/home/ju/.openclaw/media/tool-image-generation/file---hash.png"
}
```

**`message` tool_result:**
```json
{
  "content": [{"type": "text", "text": "Sent visible reply to the current webchat conversation via internal-ui."}],
  "details": {"status": "ok", "deliveryStatus": "sent", "channel": "webchat", "target": "current-run"}
}
```

### 3. Reproduce the Halting Behavior

Attempt to reproduce by:
1. Restoring backup data to `data/` directory
2. Opening dashboard in browser
3. Checking browser console for the exact error
4. If no error in console, it's a silent abort → trace with debugger breakpoints

### 4. Test Candidate Fix Approaches

**Approach A: Per-event try-catch with error placeholder (Recommended)**

```javascript
rendered.forEach((ev, idx) => {
    const fullIdx = sliceFrom + idx;
    try {
        // existing render logic
    } catch (err) {
        console.error('[render] Error rendering event', idx, ev.type, err);
        parts.push('<div class="msg msg-run-error">'
            + '<div class="msg-header">'
            + '<span class="msg-role role-error">⚠ RENDER ERROR</span>'
            + '</div>'
            + '<div class="msg-content" style="color:var(--error)">'
            + 'Failed to render ' + escHtml(ev.type || 'unknown') + ' event'
            + '</div></div>');
    }
});
```

**Approach B: Whole-session try-catch (fallback)**

Wrap the entire body of `showSessionContent` in try-catch. Simpler but less granular — if one event fails, the whole session shows an error message instead of partial content.

**Approach C: Specific fix for `image_generate`/`message`**

Add dedicated renderers for `image_generate` and `message` tools. This would prevent them from going through the generic path and potentially fix the specific trigger, but wouldn't solve the root problem of unhandled exceptions.

### 5. Add Console Diagnostics on Load

Add a log line after `showSessionContent` completes successfully so we can tell the difference between "render aborted" and "render completed but empty":

```javascript
console.log('[render] showSessionContent complete:', parts.length, 'parts,', eventsWithCum.length, 'events, filter:', filter);
```

## Decision

- **Approach A (per-event error boundary)** is the right structural fix — it prevents ANY single bad event from taking down the entire UI
- **Approach C (dedicated renderers)** is a nice-to-have for `image_generate` and `message` but doesn't prevent future unknown tools from causing the same crash
- Recommend **A + C**: add error boundaries for resilience, then add basic renderers for the new tools as a follow-up

## Implementation Notes

### Changes to `showSessionContent` (index.html)

Two code paths need try-catch wrapping:

1. **Full rebuild path** — the `rendered.forEach()` loop building `parts` array
2. **Incremental append path** — the `newEvents.forEach()` loop building HTML string

Both have identical structure: iterate → call `renderEvent` → push to output.

### Changes to `renderToolCall` (index.html)

Add `image_generate`, `message`, `video_generate`, `music_generate` to the switch:

```javascript
case 'image_generate': html = renderImageGenCall(ev, inp, idx); break;
case 'message':        html = renderMessageCall(ev, inp, idx); break;
```

### Changes to `renderToolResult` (index.html)

Add `image_generate`, `message` to the switch:

```javascript
case 'image_generate': return renderImageGenResult(ev, parsed, t, idx, expanded);
case 'message':        return renderMessageResult(ev, parsed, t, idx, expanded);
```

## Implementation Summary

**Completed:** 2026-06-02

### Changes to `index.html`

1. **Error boundary:** Added `renderEventSafe()` wrapper — every `renderEvent()` call in `showSessionContent` (both full rebuild and incremental append paths) is now wrapped in try-catch. On failure, renders a visible `⚠ RENDER ERROR` placeholder instead of silently aborting.

2. **Console diagnostic:** Added `console.log` after `showSessionContent` completes with event count and filter info.

3. **Dedicated renderers** added to both `renderToolCall` and `renderToolResult` switches:

| Tool | Call Renderer | Result Renderer | CSS Class |
|------|--------------|----------------|-----------|
| `image_generate` | `renderImageGenCall` | `renderImageGenResult` | `.tc-media` (purple) |
| `message` | `renderMessageCall` | `renderMessageResult` | `.tc-msg` (cyan) |
| `video_generate` | `renderVideoGenCall` | `renderVideoGenResult` | `.tc-media` (purple) |
| `music_generate` | `renderMusicGenCall` | `renderMusicGenResult` | `.tc-media` (purple) |

4. **Call renderers** show: icon, prompt preview, model/size/count info. For message: message preview + file attachment indicator.

5. **Result renderers** show: status icon (🔄 started / ⏳ running / ✅ completed / ❌ failed), status badge, async indicator, task ID, detail text.

6. **CSS:** Added `.tc-media` (purple border-left) and `.tc-msg` (cyan border-left) styles.

7. **Generic fallback still works** for any future unknown tool types — the error boundary ensures they can't crash the UI.

## Original Research Plan (for reference)

### New Renderer Functions

- `renderImageGenCall(ev, inp, idx)` — Show prompt preview, filename, aspect ratio
- `renderImageGenResult(ev, parsed, t, idx, expanded)` — Show task status (started/running/done)
- `renderMessageCall(ev, inp, idx)` — Show message preview, file attachment indicator
- `renderMessageResult(ev, parsed, t, idx, expanded)` — Show delivery status

## Related

- [fix-session-sync-race-condition](fix-session-sync-race-condition.md) — Related performance issue on initial load
- [fix-agent-tool-events](fix-agent-tool-events.md) — Previous tool event routing fix
- [dynamic-agent-list-in-modal](dynamic-agent-list-in-modal.md) — Previous unhandled tool case
