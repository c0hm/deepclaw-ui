# Improve image_generate Tool Call/Result Rendering

**Started:** 2026-06-02
**Status:** completed
**Completed:** 2026-06-02

## Analysis

### How image_generate Works (from session data)

1. **Call**: Agent calls `image_generate` with prompt, size, aspectRatio, outputFormat, etc.
2. **Async result**: Returns `{async: true, status: "started", taskId: "..."}`, `terminate: true`
3. **Completion**: System event arrives when image is done; image saved to `~/.openclaw/media/tool-image-generation/<filename>.png`
4. **Agent retrieves**: Agent uses `exec` to `cp` the file to target location

### Full Parameter Set (from tool spec in system prompt)

| Param | Type | Description |
|-------|------|-------------|
| `action` | string | "generate" (default), "status", "list" |
| `prompt` | string | Image generation prompt |
| `image` | string | Single reference image path/URL (for edits) |
| `images` | array | Reference images (max 10) |
| `model` | string | Provider/model override |
| `filename` | string | Output filename hint |
| `size` | string | e.g. "1792x1024" |
| `aspectRatio` | string | e.g. "16:9", "1:1" |
| `resolution` | string | "1K", "2K", "4K" |
| `quality` | string | "low", "medium", "high", "auto" |
| `outputFormat` | string | "png", "jpeg", "webp" |
| `background` | string | "transparent", "opaque", "auto" |
| `openai` | object | { background, moderation, outputCompression, user } |
| `fal` | object | { creativity: "raw"|"low"|"medium"|"high" } |
| `count` | number | 1-4 images |
| `timeoutMs` | number | Provider timeout |

### Result Shapes

**action=generate (started):**
```json
{
  "content": [{ "type": "text", "text": "Background task started..." }],
  "details": { "async": true, "status": "started", "taskId": "...", "runId": "...", "size": "...", "outputFormat": "..." },
  "terminate": true
}
```

**action=list:**
```json
{
  "content": [{ "type": "text", "text": "provider list..." }],
  "details": { "kind": "image_generation", "providers": [...] }
}
```

**action=status:**
```json
{
  "content": [{ "type": "text", "text": "Task ... is already running..." }],
  "details": { "action": "status", "async": true, "active": true, "status": "running", "provider": "...", "progressSummary": "..." }
}
```

## Gaps in Current Renderers

### `renderImageGenCall` (tool_start)
Missing params:
- [ ] `action` mode (list/status/generate) — shows prompt even for status calls
- [ ] `image` / `images` reference media
- [ ] `background` transparency
- [ ] `openai` nested settings
- [ ] `fal` nested settings
- [ ] `timeoutMs`
- [ ] `resolution`

### `renderImageGenResult` (tool_result)
Missing handling:
- [ ] `action=list` — providers/models as structured table (not plain text)
- [ ] `action=status` — progress display, provider info
- [ ] Image filename/path when in details
- [ ] Better async task display

## Plan

1. Rewrite `renderImageGenCall` to handle all params and action modes
2. Rewrite `renderImageGenResult` to handle all result types
3. Apply same patterns to `video_generate` and `music_generate` (they share the same gaps)
4. Update docs
