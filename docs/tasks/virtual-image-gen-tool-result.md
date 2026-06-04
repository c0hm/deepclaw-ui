# Virtual Tool Result for Async Image Generation Completion

**Started:** 2026-06-02
**Status:** implemented ✅ (2026-06-02)

## What Works

Tested with two real image generations — virtual `tool_result` injected correctly:
- ✅ `image_generate` → `tool_result { status: "started", taskId: "..." }`
- ✅ Completion run arrives as `message` tool_start with `runId: image_generate:<taskId>:ok`
- ✅ Backend detects, extracts `filePath` from input, creates media token
- ✅ Virtual `tool_result` injected with `status: "completed"`, `mediaToken`, `filename`, `prompt`, `size`
- ✅ Frontend renders completed image inline (clickable → opens full in new tab)
- ✅ Failed status renders red error styling
- ✅ Video/music completion support (via `<video>`/`<audio>` elements)
- ✅ Survives page reloads (persisted to disk via `session.addEvent()`)
- ✅ Survives server restart (media tokens re-registered in `SessionState.load()`)
- ✅ Auto-expands completed results (image visible immediately without clicking)
- ✅ LLM caption from message tool shown as styled subtitle
- ✅ Media token cleanup: LRU eviction (100-entry cap) + TTL expiry (7d/24h)

## Implementation Details

### Two delivery patterns detected:

**Pattern A (message tool)** — current/production:
```
run_start → runId: image_generate:<taskId>:ok
tool_start message → input.filePath = "/path/to/image.png"
tool_result message → deliveryStatus: "sent"
```
Extract `filePath` directly from message input.

**Pattern B (exec cp)** — older/fallback:
```
tool_start exec → command: cp "SRC" "DST"
tool_result exec
```
Parse `cp "..." "..."` from command string, prefer target file.

### File path fallback:
If `filePath` doesn't exist at the given path, tries `~/.openclaw/media/tool-image-generation/<basename>` as container path fallback (for when path refers to different mount).

### Idempotency:
- Runtime: `completedMediaTaskIds` Set per process
- Persistent: scans for existing `isVirtual` events with same taskId

## Open / Remaining Improvements

### 1. Auto-expand completed results ✅ (2026-06-02)
All three renderers (`renderImageGenResult`, `renderVideoGenResult`, `renderMusicGenResult`) now auto-expand when `d.status === 'completed'` via `expandClass = ' tr-expanded'`.

### 2. Show LLM-generated caption from message tool ✅ (2026-06-02)
Backend Pattern A detection extracts `inp.message` as `caption`, stored in `details.caption`. Frontend renders it as a styled subtitle (italic, blue, left-accent border with 💬 icon) above the media element.

### 3. Show reference images used
If the original `image_generate` call used reference images (`image`/`images` params), the completed result could show thumbnails of the reference images used.

### 4. Video/audio completion (untested)
Video and music generation completion patterns not yet tested end-to-end. The backend detection handles them (regex captures `video_generate` and `music_generate`), and frontend renderers have `<video>`/`<audio>` display logic, but real completion flow may differ (e.g., different delivery pattern).

### 5. Cleanup old media tokens ✅ (2026-06-02)
Implemented LRU eviction (cap at 100 entries, evicts oldest by `createdAt`) and TTL expiry (7d since creation, 24h idle) checked on each serve. `createdAt` and `lastAccessed` timestamps added to all media token entries.

### 6. Error completion display
Failed completions (`runId: ...:error`) are not yet tested. The backend creates `isError: true` virtual events, and frontend renders red error styling, but the error message content may need better formatting.

## Problem

`image_generate` (and `video_generate` / `music_generate`) are async:

1. `tool_start` → prompt, size, etc.
2. `tool_result` → `{ status: "started", taskId: "..." }` — just says "background task started"
3. **Time passes...** (seconds to minutes)
4. Completion arrives as a **system event** with a new run — the agent runs `exec cp` to move the generated file
5. There is **no tool_result** that pairs the completed image back to the original call

The UI currently shows the "started" result but never shows the completed image or path.

## Goal

When image generation completes, inject a **virtual `tool_result`** into the session that pairs back to the original `tool_start` via `toolCallId`, and shows:
- ✅ Status badge: `completed` or `failed`
- Image filename and prompt preview
- The actual image rendered inline (for images) or a link (for video/audio)
- Full prompt in expanded body

---

## Deep Analysis: All Implementation Options

### Signal: How Completion Arrives

The key signal is that the completion run has a distinctive `runId`:

```
runId = "image_generate:37efe6bf-c05c-...:ok"     // success
runId = "image_generate:37efe6bf-c05c-...:error"   // failure
```

This `runId` is set on ALL events in the completion run, including:
- `run_start` (model: `claude-sonnet-4-20250514-gateway-wrap`)
- `thinking` text
- `tool_start` for `exec` (the `cp` command)
- `tool_result` for `exec`

**Critical insight:** The exec's `tool_start` has `runId = "image_generate:<taskId>:ok"`, but the exec has its own `toolCallId`. The virtual event must pair back to the ORIGINAL `image_generate`'s `toolCallId`, not the exec's.

---

### Option A: Backend Virtual Event Injection (RECOMMENDED)

**Detection point:** In `handleGatewayMessage()`, after `session.addEvent()` for each event, check if the event is a `tool_result` for `exec` with a completion-pattern `runId`.

**Full pipeline:**
1. `convertToFrontendEvent()` produces `tool_result` for `exec` with `toolCallId = "call_00_YYY"`
2. After `session.addEvent(ev)`, check `tryDetectMediaCompletion(ev, session)`
3. Function finds the matching `tool_start` for the same `toolCallId` in `session.events`
4. If `runId` matches `/^(image|video|music)_generate:([^:]+):(ok|error)$/`, proceed
5. Extract `taskId`, find original generate `tool_result` in `session.events` (by taskId)
6. Get original `toolCallId` and `runId` from that
7. Find original `tool_start` for prompt/size/format
8. Parse image path from exec's `command` field
9. Create virtual `tool_result` with:
   - `runId`: same as original image_generate tool_start
   - `toolCallId`: same as original image_generate
   - `isVirtual: true`: flag
   - `result`: JSON envelope with `{ content, details: { status:'completed', mediaToken, imagePath, prompt, taskId } }`
10. `session.addEvent(virtualResult)` → persisted, broadcast

**Media serving (images in `<img>` tags):**
- Backend creates a `mediaToken` (UUID) mapped to the image path
- New endpoint `GET /api/media/serve/:token` — serves file with correct Content-Type (NOT one-shot, NOT consumed)
- On server restart, `SessionState.load()` re-registers tokens from persisted virtual events

**Pros:**
- ✅ Survives page reloads (persisted to disk via `session.addEvent()`)
- ✅ Visible in JSON viewer
- ✅ Clean data model — a real event in the session
- ✅ Frontend renderer already handles `status: "completed"` — just needs image display
- ✅ `session.addEvent()` handles dedup, save, and broadcast
- ✅ Backend has full context (all events, session state)
- ✅ Media tokens survive server restart (re-registered from disk)

**Cons:**
- ❌ Touches backend event pipeline (must be careful)
- ❌ Backwards scan of session events (O(n), bounded by max 2000)
- ❌ Need to handle edge cases (race conditions, duplicate completions, error completions)

---

### Option A1: Intercept at `run_start` Level (sub-variant)

**Instead of waiting for exec `tool_result`, intercept the `run_start` with completion pattern.**

1. In `handleGatewayMessage()`, when `run_start` arrives with `runId` matching completion pattern
2. Set a pending flag: `pendingMediaCompletions[runId] = { taskId, ts }`
3. Later, when `tool_result` for `exec` arrives in the same run, use the flag to trigger virtual result creation

**Pros:** Earlier detection point, can show "completing..." state sooner

**Cons:** More state management, must handle cleanup if exec fails or is aborted, run_start arrives as a converted event before exec

---

### Option A2: Intercept Directly at `convertToFrontendEvent()` (sub-variant)

Modify `convertToFrontendEvent()` itself to detect the pattern.

**Pros:** Cleaner separation — detection logic lives with event conversion

**Cons:** `convertToFrontendEvent` has no access to `session.events` (can't scan backwards), can't look up the original generate call, can't create the virtual event there — would need a callback or return extra metadata

---

### Option B: Frontend-Only Inline Rendering

Detect the completion pattern in `showSessionContent()` or `handleGatewayMsg()` and render a virtual card without modifying the event array.

**Detection:** When rendering an exec `tool_result`, check if the exec's parent `tool_start` has `runId` matching the pattern. Scan `sessionEvents` backwards for the matching `image_generate` `tool_start`. Render a virtual completion card inline.

**Pros:**
- ✅ No backend changes needed
- ✅ No persistence issues

**Cons:**
- ❌ Virtual card disappears on page reload (not in stored events)
- ❌ Not visible in JSON viewer
- ❌ Fragile — depends on DOM manipulation outside the event model
- ❌ Must handle cross-session boundary lookups
- ❌ Image serving still needs backend (or inline base64)

---

### Option C: Dedicated Completion Endpoint

Backend exposes an endpoint like `/api/session/:key/completions` that returns all pending/completed media tasks for a session. Frontend polls or detects and fetches.

**Pros:** Clean data model

**Cons:**
- ❌ Requires polling (not real-time enough)
- ❌ Two-phase rendering (event arrives → fetch completion → render)
- ❌ Adds HTTP roundtrips
- ❌ More complex than any other option

---

### Option D: Parse Exec Commands (sub-option for path extraction)

Instead of detecting by runId pattern, detect by parsing exec commands that reference `tool-image-generation` directory.

```javascript
if (cmd.includes('tool-image-generation')) {
  const pathMatch = cmd.match(/(\/[^\s"']*tool-image-generation\/[^\s"']+)/);
  mediaPath = pathMatch[1];
}
```

**Pros:** More robust to runId format changes

**Cons:**
- ❌ Fragile to command format (agent might use `mv`, `rsync`, `install`, etc.)
- ❌ Can't determine which generate call this is for (no taskId match)
- ❌ False positives if agent references tool-image-generation in other contexts
- ❌ Too tightly coupled to implementation detail

---

### Option E: Gateway-Level Solution (future)

Add a `media.generate.complete` gateway event that fires when async generation completes, with structured data (image path, prompt, taskId). The UI would handle this as a first-class event.

**Pros:** Cleanest architecture long-term

**Cons:**
- ❌ Requires gateway changes (out of scope)
- ❌ Doesn't work with current gateway

---

## Image Serving Options (sub-decision)

For displaying the actual image in the frontend:

| # | Approach | Reusable | Survives Restart | Survives Reload | Notes |
|---|----------|----------|-------------------|-----------------|-------|
| 1 | One-shot file share token | No ❌ | No ❌ | No ❌ | Consumed on first render, 60s TTL |
| 2 | Reusable media token (`/api/media/serve/:token`) | Yes ✅ | Yes* ✅ | Yes ✅ | *Re-register on session load |
| 3 | Base64 inline in event | Yes ✅ | Yes ✅ | Yes ✅ | Bloats session JSON, huge for images |
| 4 | Path-based direct serve (`/api/media?path=...`) | Yes ✅ | Yes ✅ | Yes ✅ | Ugly URLs, path in query string |
| 5 | Static file serve with auth | Yes ✅ | Yes ✅ | Yes ✅ | Complex, needs auth middleware |

**Selected: Option 2 — reusable media token with restart recovery**

- Non-consumable token (unlike file sharing)
- Survives page reloads (token in persisted event)
- Survives server restart (re-registered in `SessionState.load()`)
- Clean URL: `/api/media/serve/<uuid>`
- Content-Type detected from extension
- Security: whitelist paths to `~/.openclaw/media/`

**Security check on serve:**
```javascript
const MEDIA_ALLOWED_PREFIX = path.join(os.homedir(), '.openclaw', 'media');
if (!resolved.startsWith(MEDIA_ALLOWED_PREFIX)) return 403;
```

---

## Final Architecture: Option A + Option 2

### Backend (`miniclaw-ui.js`)

#### 1. New state
```javascript
const mediaTokens = new Map(); // token → { path, mimeType }
const completedMediaTaskIds = new Set(); // taskId → true (dedup)
```

#### 2. Detection in `handleGatewayMessage()`

After the existing event processing loop, add:

```javascript
// After events.forEach loop where session.addEvent(ev) is called:
events.forEach(ev => {
  // ... existing code
  session.addEvent(ev);
  
  // NEW: detect async media completion
  if (ev.type === 'tool_result' && ev.toolName === 'exec') {
    tryDetectMediaCompletion(ev, session);
  }
});
```

#### 3. `tryDetectMediaCompletion(execResult, session)`

```javascript
function tryDetectMediaCompletion(execResult, session) {
  // 1. Find matching exec tool_start (scan backwards, max 50)
  let execStart = null;
  for (let i = session.events.length - 1; i >= 0 && i >= session.events.length - 50; i--) {
    if (session.events[i].type === 'tool_start' &&
        session.events[i].toolName === 'exec' &&
        session.events[i].toolCallId === execResult.toolCallId) {
      execStart = session.events[i];
      break;
    }
  }
  if (!execStart) return;
  
  // 2. Check runId for completion pattern
  const match = execStart.runId.match(
    /^(image_generate|video_generate|music_generate):([^:]+):(ok|error)$/
  );
  if (!match) return;
  
  const [, mediaType, taskId, status] = match;
  
  // 3. Idempotency check — runtime (prevents duplicates in same process lifetime)
  if (completedMediaTaskIds.has(taskId)) return;
  completedMediaTaskIds.add(taskId);
  
  // 3b. Idempotency check — persistent (prevents duplicates after server restart,
  //     when gateway re-sends completion runs and virtual events are already on disk)
  for (let i = session.events.length - 1; i >= 0; i--) {
    const ev = session.events[i];
    if (ev.isVirtual && ev.toolName === mediaType) {
      try {
        const p = JSON.parse(ev.result);
        if (p?.details?.taskId === taskId) return; // already persisted
      } catch {}
    }
  }
  
  // 4. Find original media generate tool_result (by taskId, max 300 events)
  let origResult = null;
  for (let i = session.events.length - 1; i >= 0 && i >= session.events.length - 300; i--) {
    const ev = session.events[i];
    if (ev.type === 'tool_result' && ev.toolName === mediaType) {
      try {
        const parsed = JSON.parse(ev.result);
        if (parsed?.details?.taskId === taskId) {
          origResult = ev;
          break;
        }
      } catch {}
    }
  }
  if (!origResult) return;
  
  // 5. Find original media generate tool_start (same toolCallId, max 300)
  let origStart = null;
  for (let i = session.events.length - 1; i >= 0 && i >= session.events.length - 300; i--) {
    if (session.events[i].type === 'tool_start' &&
        session.events[i].toolName === mediaType &&
        session.events[i].toolCallId === origResult.toolCallId) {
      origStart = session.events[i];
      break;
    }
  }
  if (!origStart) return;
  
  // 6. Extract media path from exec command
  let mediaPath = '';
  let mediaFilename = '';
  if (status === 'ok') {
    const cmd = execStart.input?.command || '';
    // Parse: cp "SOURCE" "TARGET" — prefer target, fallback to source
    const cpMatch = cmd.match(/cp\s+"([^"]+)"\s+"([^"]+)"/);
    if (cpMatch) {
      const srcPath = cpMatch[1];
      const dstPath = cpMatch[2];
      // Use whichever exists, prefer target
      if (fs.existsSync(dstPath)) {
        mediaPath = dstPath;
      } else if (fs.existsSync(srcPath)) {
        mediaPath = srcPath;
      }
      mediaFilename = path.basename(mediaPath);
    }
  }
  
  // 7. Create media token
  let mediaToken = '';
  if (mediaPath && fs.existsSync(mediaPath)) {
    mediaToken = crypto.randomUUID();
    const ext = path.extname(mediaPath).toLowerCase();
    const MIME_MAP = {
      '.png': 'image/png', '.jpg': 'image/jpeg', '.jpeg': 'image/jpeg',
      '.gif': 'image/gif', '.webp': 'image/webp', '.svg': 'image/svg+xml',
      '.bmp': 'image/bmp',
      '.mp4': 'video/mp4', '.webm': 'video/webm', '.mov': 'video/quicktime',
      '.mp3': 'audio/mpeg', '.wav': 'audio/wav', '.ogg': 'audio/ogg',
      '.flac': 'audio/flac', '.aac': 'audio/aac', '.m4a': 'audio/mp4'
    };
    mediaTokens.set(mediaToken, {
      path: mediaPath,
      mimeType: MIME_MAP[ext] || 'application/octet-stream'
    });
  }
  
  // 8. Create virtual tool_result
  const origPrompt = typeof origStart.input === 'string'
    ? (() => { try { return JSON.parse(origStart.input).prompt || ''; } catch { return ''; } })()
    : (origStart.input?.prompt || '');
  const origSize = typeof origStart.input === 'string'
    ? (() => { try { return JSON.parse(origStart.input).size || ''; } catch { return ''; } })()
    : (origStart.input?.size || '');
  const origFormat = typeof origStart.input === 'string'
    ? (() => { try { return JSON.parse(origStart.input).outputFormat || ''; } catch { return ''; } })()
    : (origStart.input?.outputFormat || '');
  
  const details = {
    status: status === 'ok' ? 'completed' : 'failed',
    async: true,
    taskId,
    prompt: origPrompt,
    size: origSize,
    outputFormat: origFormat
  };
  if (mediaToken) details.mediaToken = mediaToken;
  if (mediaPath) details.mediaPath = mediaPath;
  if (mediaFilename) details.filename = mediaFilename;
  
  const virtualResult = {
    type: 'tool_result',
    runId: origStart.runId,           // original image_generate runId
    toolName: mediaType,
    toolCallId: origResult.toolCallId, // pairs with original tool_start
    result: JSON.stringify({
      content: [{
        type: 'text',
        text: status === 'ok'
          ? `${mediaType} completed → ${mediaFilename || 'file'}`
          : `${mediaType} failed`
      }],
      details
    }),
    isError: status !== 'ok',
    isVirtual: true,
    ts: new Date()
  };
  
  // 9. Add to session (persisted, broadcast, deduped)
  session.addEvent(virtualResult);
  
  log('info', `Virtual ${mediaType} result injected: taskId=${taskId}, status=${status}, token=${mediaToken || 'none'}`);
}
```

**Why scan only last 50/300 events:** The exec tool_start is always very recent (same run). The original generate call could be further back (different run, different session potentially). 300 events is a generous window. If the original generate call is older than 300 events, the session has been very active — this is an acceptable edge case to miss.

#### 4. Media serving endpoint

```javascript
// In handleRequest():
// GET /api/media/serve/:token
const mediaServeMatch = parsedUrl.pathname.match(/^\/api\/media\/serve\/([^/]+)$/);
if (mediaServeMatch) {
  const token = mediaServeMatch[1];
  const entry = mediaTokens.get(token);

  if (!entry) {
    res.writeHead(410, { 'Content-Type': 'text/plain' });
    res.end('Media token expired or invalid');
    return;
  }

  // Security check: path must be under ~/.openclaw/media/
  const mediaDir = path.join(os.homedir(), '.openclaw', 'media');
  const resolved = path.resolve(entry.path);
  if (!resolved.startsWith(mediaDir)) {
    res.writeHead(403, { 'Content-Type': 'text/plain' });
    res.end('Access denied');
    return;
  }

  if (!fs.existsSync(resolved)) {
    res.writeHead(404, { 'Content-Type': 'text/plain' });
    res.end('File not found');
    return;
  }

  res.writeHead(200, {
    'Content-Type': entry.mimeType || 'application/octet-stream',
    'Cache-Control': 'public, max-age=3600',
    'Access-Control-Allow-Origin': '*'
  });
  const readStream = fs.createReadStream(resolved);
  readStream.pipe(res);
  readStream.on('error', () => {
    if (!res.headersSent) {
      res.writeHead(500);
      res.end('Error reading file');
    }
  });
  return;
}
```

#### 5. Token recovery on session load

In `SessionState.load()`, after loading events:

```javascript
// Re-register media tokens from persisted virtual events
for (const ev of this.events) {
  if (ev.isVirtual && ev.toolName &&
      /^(image_generate|video_generate|music_generate)$/.test(ev.toolName)) {
    try {
      const parsed = JSON.parse(ev.result);
      const d = parsed?.details;
      if (d?.mediaToken && d?.mediaPath) {
        const resolved = path.resolve(d.mediaPath);
        const mediaDir = path.join(os.homedir(), '.openclaw', 'media');
        if (fs.existsSync(resolved) && resolved.startsWith(mediaDir)) {
          const ext = path.extname(resolved).toLowerCase();
          const MIME_MAP = {
            '.png': 'image/png', '.jpg': 'image/jpeg', '.jpeg': 'image/jpeg',
            '.gif': 'image/gif', '.webp': 'image/webp', '.svg': 'image/svg+xml',
            '.bmp': 'image/bmp',
            '.mp4': 'video/mp4', '.webm': 'video/webm', '.mov': 'video/quicktime',
            '.mp3': 'audio/mpeg', '.wav': 'audio/wav', '.ogg': 'audio/ogg',
            '.flac': 'audio/flac', '.aac': 'audio/aac', '.m4a': 'audio/mp4'
          };
          mediaTokens.set(d.mediaToken, {
            path: resolved,
            mimeType: MIME_MAP[ext] || 'application/octet-stream'
          });
        }
      }
    } catch {}
  }
}
```

### Frontend (`index.html`)

#### 1. Update `renderImageGenResult` (lines ~2674–2758)

Add completed image display for `status: 'completed'`:

```javascript
// In the generate/async section, after the status determination:
if (action === 'generate' || !action) {
  // ... existing status icon/label code ...
  
  // NEW: completed image display
  if (d.status === 'completed' && d.mediaToken) {
    var imgHtml = '<div style="margin-top:8px;text-align:center;">' +
      '<img src="/api/media/serve/' + escAttr(d.mediaToken) + '" ' +
        'style="max-width:100%;max-height:500px;border-radius:6px;display:block;cursor:pointer;" ' +
        'alt="' + escAttr(d.prompt || 'Generated image') + '" ' +
        'loading="lazy" ' +
        'onclick="window.open(\'/api/media/serve/' + escAttr(d.mediaToken) + '\', \'_blank\')" ' +
        'title="Click to view full size" />' +
      (d.filename ? '<div style="font-size:10px;color:var(--muted);margin-top:4px;">' + escHtml(d.filename) + '</div>' : '') +
      '</div>';
    bodyContent = imgHtml + bodyContent;
  }
  
  if (d.status === 'failed') {
    errorClass = ' tr-error';
    statusIcon = '❌';
    statusLabel = 'failed';
    bodyContent = '<div style="color:var(--error);font-size:11px;padding:8px;background:#1a1b26;border-radius:4px;margin-top:4px;">' +
      escHtml(parsed.text || 'Image generation failed') + '</div>' + bodyContent;
  }
  
  // ... rest of existing code ...
}
```

#### 2. Update `renderVideoGenResult`

Similar — when `status: 'completed'` with `mediaToken`:
- Show `<video>` element with controls for video types
- Or show download link for audio

```javascript
if (d.status === 'completed' && d.mediaToken) {
  if (mediaTypeIsVideo) {
    bodyContent = '<div style="margin-top:8px;">' +
      '<video controls style="max-width:100%;max-height:400px;border-radius:6px;" ' +
        'src="/api/media/serve/' + escAttr(d.mediaToken) + '"></video>' +
      '</div>' + bodyContent;
  }
}
```

#### 3. Update `renderMusicGenResult`

When `status: 'completed'` with `mediaToken`:
- Show `<audio>` element with controls
- Show download link

```javascript
if (d.status === 'completed' && d.mediaToken) {
  bodyContent = '<div style="margin-top:8px;">' +
    '<audio controls style="width:100%;" src="/api/media/serve/' + escAttr(d.mediaToken) + '"></audio>' +
    '<div style="font-size:10px;color:var(--muted);margin-top:4px;">' +
      '<a href="/api/media/serve/' + escAttr(d.mediaToken) + '" target="_blank">⬇ Download ' + escHtml(d.filename || 'file') + '</a>' +
    '</div>' +
    '</div>' + bodyContent;
}
```

---

## Edge Cases

| Case | Handling |
|------|----------|
| **Completion arrives before started result** | Backwards scan fails (original events not yet in session). Completion is silently skipped — the next completion arrival would work. In practice, the generate run completes before the completion run starts, so this shouldn't happen. |
| **Duplicate completion** | `completedMediaTaskIds` Set prevents duplicate virtual events for the same taskId. |
| **Error completion** | `runId` ends with `:error` → virtual result has `isError: true`, `status: 'failed'`, no media token, red error styling. |
| **Completion in a different session** | Possible if the completion run is in a different session than the original generate call. The backwards scan searches the CURRENT session only — scan window should be large enough (300 events) to cross session boundaries in most cases. If the original generate event isn't found, fallback: create virtual event with just taskId and filename (no prompt/size from original). |
| **Completion in subagent session** | The completion runs in the parent session, not the subagent. The virtual event is added to the parent session. If the original generate call is ONLY in the subagent (not forwarded to parent), the backward scan won't find it — skip gracefully, no virtual event. |
| **Gateway re-send after restart** | On reconnect, gateway may re-send completion runs. Virtual events already persisted on disk. Step 3b scans for existing virtual events by taskId and skips if found. |
| **Page reload** | Virtual event is persisted to disk. On reload, `session.sync` includes the virtual event. Media token is re-registered on server restart. Inline image renders. |
| **Server restart** | `SessionState.load()` re-registers all media tokens from persisted virtual events. Images render on page load. |
| **Image deleted from disk** | Media serving returns 404. Image shows broken placeholder. Acceptable — the image was moved/deleted externally. |
| **Tool-image-generation dir not under homedir** | It's always `~/.openclaw/media/tool-image-generation/`, which IS under `os.homedir()`. The security check at serve time validates this. |
| **Multiple images generated** | Each has a unique `taskId` → unique `completedMediaTaskIds` entry → unique virtual event. |
| **Large images** | Served via streaming (`fs.createReadStream`). No size limit. CSS `max-height: 500px` constrains inline display. Click to open full size. |

---

## What's NOT Changed

- **Exec events are kept** — the `exec cp` tool_start + tool_result remain in the session as normal events. The virtual event is supplementary.
- **File sharing system** — unchanged. The new `/api/media/serve/:token` is separate.
- **Session sizing** — virtual events count toward the 2000 event limit, same as any other event.

## What MUST Change (critical)

### 🔴 `_makeEventKey()` — add `result` field

**Problem:** The current dedup key for `tool_result` events is:
```
[type, runId, toolName, toolCallId]
```

For both the original "started" AND the virtual "completed" `tool_result`:
```
tool_result|<sameRunId>|image_generate|<sameToolCallId>
```
**These are identical → the virtual event would be silently dropped by `addEvent()`.**

**Fix:** Add `ev.result` to the dedup key:
```javascript
_makeEventKey(ev) {
  const parts = [ev.type || '', ev.runId || ''];
  if (ev.text) parts.push(hashString(ev.text));
  if (ev.toolName) parts.push(ev.toolName);
  if (ev.toolCallId) parts.push(ev.toolCallId);
  if (ev.input) parts.push(hashString(typeof ev.input === 'string' ? ev.input : JSON.stringify(ev.input)));
  if (ev.result) parts.push(hashString(typeof ev.result === 'string' ? ev.result : JSON.stringify(ev.result))); // ← NEW
  return parts.join('|');
}
```

**Why this is safe:**
- The original result is `{"status":"started","taskId":"..."}` 
- The virtual result is `{"status":"completed","prompt":"...","mediaToken":"..."}`
- Different content → different hash → no collision
- Previously, this wouldn't have caused issues because no tool emits multiple `tool_result` events for the same `toolCallId` with different content. Image/video/music generation is the first tool that needs this.
- This also fixes a latent issue: if a tool ever emits `update` phase events with different content, they'd now correctly not be deduped.

---

## Video / Music Generation

The same pattern applies. Differences:
- RunId patterns: `video_generate:<taskId>:ok`, `music_generate:<taskId>:ok`
- Media display: `<video>` or `<audio>` elements instead of `<img>`
- Same `tryDetectMediaCompletion()` handles all three types (the regex captures the media type)
- Same media token system serves any file type

---

## Implementation Order

1. **Backend: media token store + endpoint** — `/api/media/serve/:token` — 30 min
2. **Backend: `tryDetectMediaCompletion()`** — detection logic — 45 min
3. **Backend: `SessionState.load()` token recovery** — 15 min
4. **Frontend: `renderImageGenResult` completed display** — 20 min
5. **Frontend: `renderVideoGenResult` completed display** — 15 min
6. **Frontend: `renderMusicGenResult` completed display** — 15 min
7. **Test with actual async generation** — verify end-to-end — 15 min

**Total estimate:** ~2.5 hours

---

## Testing Plan

1. **Happy path:** Send an image generation request → verify virtual `tool_result` appears with completed status
2. **Image rendering:** Verify the image loads inline in the UI
3. **Page reload:** Reload browser → verify image still shows
4. **Server restart:** Restart miniclaw-ui → reload browser → verify image still shows
5. **Error path:** Force an image generation failure → verify failed status with red styling
6. **Dedup:** Send two completions for the same taskId → verify only one virtual event
7. **Multiple generations:** Generate two images → verify both show completed
8. **Video/music:** Test video_generate and music_generate completions

---

## Open Questions

1. **What does the raw completion system event look like?** The session data shows only the agent's response (thinking + exec cp). Is there a system-level event before that which contains more structured data about the completion? If so, intercepting that would be cleaner than parsing exec commands.

2. **What if `FILE_SHARE_ALLOWED_PREFIXES` doesn't include `os.homedir()` in the future?** The media serving has its own security check (`~/.openclaw/media/`), independent of the file sharing system.

3. **Should the virtual event replace or supplement the "started" tool_result?** Supplement (not replace). The "started" result shows the initial state. The "completed" virtual result shows the final state. Both are useful for understanding the lifecycle.
