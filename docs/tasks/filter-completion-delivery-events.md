# Filter Noisy Completion Delivery Events

**Started:** 2026-06-02
**Completed:** 2026-06-02
**Status:** done

## Problem

When an async generation (image/video/music) completes, OpenClaw fires a `message` tool to deliver the result back to the chat. This produces 2 noisy events:

| Event | Shows in UI | Reality |
|-------|------------|---------|
| `tool_start message` | `💬 message "🐚 A glowing sea..." 📎 file` | Delivery plumbing — caption is already in virtual result |
| `tool_result message` | `💬 message → sent ✅` | Delivery confirmation — no user value |

All meaningful info (caption, filePath, inline image) is already in the **virtual `tool_result`** (D) that `tryDetectMediaCompletion` injects. C and E are pure noise.

### Full Event Lifecycle

```
A: tool_start image_generate  → ✅ renders as "🖼️ image_gen 🔄 started"
B: tool_result image_generate → ✅ renders as "🖼️ image_gen 🔄 started · async"
C: tool_start message         → ❌ noise (LLM's delivery message, already in D)
D: tool_result image_generate → ✅ virtual result: "✅ completed" + inline image
E: tool_result message        → ❌ noise ("sent" status badge)
```

**A + D = complete UX.** C and E are delivery artifacts from OpenClaw's internal routing.

## Chosen Approach: Backend Filter (Option A, refined)

Filter at `handleGatewayMessage` time — events never reach `session.events`, never broadcast to frontend, never persisted.

### Why not other approaches?

- **Option B (frontend filter):** Events still take session space, still broadcast, still persisted. Filter logic leaks into render pipeline.
- **Option C (isDeliveryArtifact flag):** Requires marking both tool_start AND tool_result by tracking toolCallId across event batches. Same complexity as backend filter but leaves noise in session.
- **Option D (mutate original result):** Breaks event immutability. Can't show lifecycle (started → completed). Complex to build.

### Key Constraint: `tryDetectMediaCompletion` Must Run First

Pattern A (message tool_start) extracts caption + filePath from the event's input. If we filter the event before calling `tryDetectMediaCompletion`, the caption is lost — the virtual result won't show the LLM's description.

**Current code** (line ~2069):
```javascript
events.forEach(ev => {
  ev.sessionKey = sk;
  ev.ts = Date.now();
  session.addEvent(ev);  // ← ADDED FIRST (can't filter here without losing caption)

  if ((ev.type === 'tool_result' && ev.toolName === 'exec') ||
      (ev.type === 'tool_start' && ev.toolName === 'message')) {
    tryDetectMediaCompletion(ev, session);  // ← runs AFTER, too late to filter
  }
});
```

**Fix:** Restructure the loop so detection runs before persistence:

```javascript
events.forEach(ev => {
  ev.sessionKey = sk;
  ev.ts = Date.now();

  // ── Detect async media completion BEFORE persisting ─────────────────
  // Must run first so Pattern A (message tool_start) can extract caption
  // before we decide whether to filter the event.
  let skip = false;

  if (ev.type === 'tool_start' && ev.toolName === 'message') {
    // Pattern A: message tool_start with runId like image_generate:<taskId>:ok
    const runMatch = (ev.runId || '').match(
      /^(image_generate|video_generate|music_generate):[^:]+:(ok|error)$/
    );
    if (runMatch) {
      tryDetectMediaCompletion(ev, session); // extract caption + filePath first
      skip = true; // filter this tool_start
      // Track toolCallId so we can filter the matching tool_result too
      completionDeliveryCallIds.add(ev.toolCallId);
    }
  }

  if (ev.type === 'tool_result' && ev.toolName === 'message') {
    // Filter tool_result if its tool_start was a completion delivery
    if (completionDeliveryCallIds.has(ev.toolCallId)) {
      completionDeliveryCallIds.delete(ev.toolCallId); // cleanup
      skip = true;
    }
  }

  // Pattern B (exec tool_result) is NOT filtered — exec cp events are meaningful.
  // Still run detection, but AFTER persisting (needs to search event list for
  // matching exec tool_start). Pattern B always runs post-addEvent.
  if (!skip && ev.type === 'tool_result' && ev.toolName === 'exec') {
    // Will be handled after addEvent below — exec doesn't need pre-detection
  }

  if (!skip) {
    session.addEvent(ev);
  }

  // Pattern B detection — runs AFTER addEvent, searches backwards in event list
  if (ev.type === 'tool_result' && ev.toolName === 'exec') {
    tryDetectMediaCompletion(ev, session);
  }

  // ... rest of loop (token updates, run_end tracking) ...
});
```

**Note on Pattern B:** `exec` events for cp commands are NOT filtered. They represent actual tool calls with meaningful output (file copy from managed media dir). The user may want to inspect these. Only `message` delivery events are filtered.

## What Changes

### Backend (`deepclaw-ui.js`)

**File:** `deepclaw-ui.js`
**Section:** `handleGatewayMessage` event loop (around line ~2065)

Changes:
1. Add a `Set` to track completion delivery `toolCallId`s (module-level, near `completedMediaTaskIds`)
2. Restructure the event loop: Pattern A detection + filter before `addEvent`, Pattern B still after
3. Filter: message tool_start with completion runId → skip + track toolCallId
4. Filter: message tool_result with tracked toolCallId → skip + cleanup

### Module-level addition (near line ~600, after `completedMediaTaskIds`):

```javascript
// Track toolCallIds of completion delivery message calls so we can
// filter both the tool_start and tool_result from display.
const completionDeliveryCallIds = new Set();
```

### Frontend

**No changes.** Events never arrive at the browser, never rendered.

### JSON viewer

Delivery events no longer visible via JSON viewer export. This is acceptable — they contain zero user-visible information (just `deliveryStatus: "sent"` on the result and internal routing params on the start). Debugging can be done from Gateway-side logs.

### Session size

Slightly smaller — 2 fewer events per async generation.

## What Does NOT Change

- `tryDetectMediaCompletion` function — unchanged, still detects both patterns
- Virtual tool_result injection (D) — unchanged
- Caption extraction — unchanged (runs before filter)
- Media token serving (`/media/`) — unchanged
- Exec-based completion (Pattern B) — unchanged
- Session persistence, dedup, broadcast — unchanged

## Edge Cases

| Case | Handling |
|------|----------|
| **Normal message tool** (not completion, e.g. user asks agent to message someone) | Not filtered — runId won't match the `:<generate_tool>:taskId:{ok,error}` pattern |
| **Completion message that fails** (`runId: ...:error`) | Still matches pattern, still filtered. Virtual result shows the failure status. |
| **Caption extraction** | `tryDetectMediaCompletion` runs BEFORE filtering — caption is preserved |
| **Exec-based completion** (Pattern B) | Not affected — exec events are never filtered |
| **Duplicate connection / replay** | Filtered events were never persisted, so they never reappear |
| **Page reload mid-generation** | If the message tool_start was already persisted before this change, it would display. After this change, new events won't persist. Old already-persisted events could be cleaned up with a migration later if needed. |
| **tool_result arrives in different batch from tool_start** | `completionDeliveryCallIds` set persists across batches within the same server process lifetime. Restart clears it, but then events load from disk — already-persisted delivery events won't be retroactively filtered (acceptable, minor edge case). |

## Verification

1. Trigger an image_generate with an LLM that completes asynchronously
2. Check the session events: only image_generate tool_start + tool_result + virtual result, no message events
3. Confirm caption appears in the virtual result
4. Confirm inline image renders correctly
5. Trigger a normal message tool (not completion) — should still render normally
6. Check session JSON export — delivery events absent

## Implementation Order

1. Add `completionDeliveryCallIds` set
2. Restructure event loop in `handleGatewayMessage`
3. Test with async image/video/music generation
4. Test with normal message tool usage
5. Verify no regression in exec-based completion (Pattern B)
