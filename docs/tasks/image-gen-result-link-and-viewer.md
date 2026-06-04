# Task: Media Gen Result Filename Links + Image Viewer Support

**Created:** 2026-06-02
**Status:** completed

## Problem

1. **tr-header for completed media generation results** (`image_generate`, `video_generate`, `music_generate`) shows `task ea2ba2c9...` — this is opaque and unhelpful. Instead, when a media file has been generated, the header should show a clickable filename link.

2. **File viewer** (one-shot `/api/files/view/:token`) doesn't support image files. Images fall through to the null-byte binary detection and show "Binary file — cannot preview". It should render them inline.

## Plan

### A. `index.html` — Filename links in media result headers

**File:** `/home/ju/miniclaw-ui/index.html`

**Affected renderers:**
- `renderImageGenResult` (~L2681)
- `renderVideoGenResult` (~L2826)
- `renderMusicGenResult` (~L2944)

**Change:** In each renderer's `detailParts` building block for `action=generate`, when `d.status === 'completed' && d.mediaToken && d.filename`:
- Replace `task <truncated-id>...` with a linked filename:
  ```html
  <a href="/api/media/serve/<token>" target="_blank"
     style="color:var(--info);text-decoration:none;"
     onclick="event.stopPropagation()"
     title="View media">.../<filename></a>
  ```
- `onclick="event.stopPropagation()"` prevents the wrapping `tr-header` click (which toggles `toggleToolResult`) from firing
- `escAttr()` is used for attribute values; `escHtml()` for display text

**Per-renderer detail ordering:**

| Renderer | Details (before status/filename) |
|----------|---------------------------------|
| `renderImageGenResult` | `async` · `provider` · `size` · `outputFormat` · **filename link** |
| `renderVideoGenResult` | `async` · `provider` · `size` · `durationSeconds` · **filename link** |
| `renderMusicGenResult` | `async` · `provider` · `durationSeconds` · `format` · **filename link** |

### B. `miniclaw-ui.js` — Image support in file viewer

**File:** `/home/ju/miniclaw-ui.js`

Three changes:

1. **`detectFileType(filePath)`** (~L222) — Add `IMG_MIME` lookup *before* the null-byte fallback:
   ```js
   const IMG_MIME = {
     png: 'image/png', jpg: 'image/jpeg', jpeg: 'image/jpeg',
     gif: 'image/gif', webp: 'image/webp', svg: 'image/svg+xml',
     bmp: 'image/bmp', ico: 'image/x-icon'
   };
   if (IMG_MIME[ext]) return { kind: 'image', mime: IMG_MIME[ext] };
   ```
   Note: `IMG_MIME` is defined inline inside `detectFileType`, not at module scope. SVG is treated as an image (rendered via `<img>` tag), not as text/XML.

2. **Viewer route** (~L1598) — Read image files as base64:
   ```js
   const fileType = detectFileType(entry.path);
   const isImage = fileType.kind === 'image';
   let content;
   if (isImage) {
     const buf = fs.readFileSync(entry.path);
     content = buf.toString('base64');
   } else {
     content = fs.readFileSync(entry.path, 'utf8');
   }
   ```

3. **`generateViewerPage(filePath, content, title)`** (~L258) — Render images inline:
   - Detect via `type.kind === 'image'` (before binary/code/markdown branches)
   - Build a `data:<mime>;base64,<content>` URI
   - Render header bar with 🖼️ icon, filename, MIME badge, Download + Close buttons
   - Main area: `<div id="img-view"><img src="data:..." alt="filename" /></div>`
   - CSS: `#img-view` is flexbox-centered; `#img-view img` has `max-width:100%; max-height:100%; object-fit:contain; border-radius:6px; box-shadow`
   - The Download button uses the data URI directly (not a Blob, since the data is already in-page)

## Files Changed

| File | Section(s) | Change |
|------|-----------|--------|
| `index.html` | `renderImageGenResult` (~L2750) | Replace task ID with linked filename when `status=completed` + `mediaToken` + `filename` |
| `index.html` | `renderVideoGenResult` (~L2890) | Same pattern — linked filename in completed header |
| `index.html` | `renderMusicGenResult` (~L3010) | Same pattern — linked filename in completed header |
| `miniclaw-ui.js` | `detectFileType` (~L233) | Add `IMG_MIME` map returning `{ kind:'image', mime:... }` for 8 extensions |
| `miniclaw-ui.js` | Viewer route (~L1598) | Detect image type; read as base64 via `fs.readFileSync` without encoding |
| `miniclaw-ui.js` | `generateViewerPage` (~L338) | Add `#img-view` branch before binary fallback; render `<img>` with data URI, Download button |

## Implementation Notes

- **Auth passthrough:** `/api/media/serve/<token>` serves media through the media token system (separate from one-shot file viewer tokens). Tokens are registered when virtual `tool_result` events are injected for async generation completions. The media serve route does not require auth for these tokens.
- **XSS hardening:** `escAttr()` is used for all URL/attribute interpolations; `escHtml()` for display text. No user-controlled strings appear unescaped in HTML.
- **SVG handling:** SVG files are base64-encoded and rendered as `<img src="data:image/svg+xml;base64,...">`. They are NOT rendered as inline SVG or text/XML — this avoids script injection risks from untrusted SVGs.
- **Backward compatibility:** When `mediaToken` or `filename` is absent from `details`, the renderers fall back to showing `task <truncated-id>...` as before.
