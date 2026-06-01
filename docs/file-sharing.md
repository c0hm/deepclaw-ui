# File Sharing

## Overview

DeepClaw UI includes a one-shot token-based file sharing system. It allows users to generate temporary URLs for files within allowed paths, with both download and inline viewer options.

## Architecture

```
Browser → POST /api/files/share?path=/tmp/report.txt
         ← { url: "/api/files/serve/{token}", viewUrl: "/api/files/view/{token}", filename: "report.txt" }

Browser → GET /api/files/serve/{token}
         ← File download (Content-Disposition: attachment) — token consumed

Browser → GET /api/files/view/{token}
         ← Full HTML page with CodeMirror 5 / marked.js — token consumed
```

## Security Model

### Path Restriction

Files can only be shared from allowed prefixes:

```javascript
const FILE_SHARE_ALLOWED_PREFIXES = [
  os.homedir(),   // e.g. /home/ju
  '/tmp'
];
```

The resolved path must start with one of these prefixes — path traversal is prevented by prefix whitelist, not by symlink or `..` blocking.

### Token Lifecycle

```javascript
const fileShareTokens = new Map();   // token → { path, timeoutHandle }
const FILE_SHARE_TTL_MS = 60_000;    // 60 seconds
```

- Tokens are UUIDv4 (`crypto.randomUUID()`)
- **One-shot**: consumed on first access (serve or view)
- **TTL**: auto-expired after 60 seconds if never accessed
- Expired/used tokens return `410 Gone` with descriptive HTML
- Token is deleted from the map AND timer is cleared on consumption

### Size Limits

- **Download (serve)**: No size limit — streamed directly
- **Viewer (view)**: Max 2MB — returns `413 Payload Too Large` HTML page if exceeded

## Endpoints

### POST /api/files/share

**Request:**
```json
{ "filePath": "/tmp/report.txt" }
```

**Success response (200):**
```json
{
  "url": "/api/files/serve/550e8400-e29b-41d4-a716-446655440000",
  "viewUrl": "/api/files/view/550e8400-e29b-41d4-a716-446655440000",
  "filename": "report.txt"
}
```

**Error responses:**
- `400` — `filePath` missing from body
- `403` — path not in allowed prefixes
- `404` — file not found on disk

### GET /api/files/serve/:token

Returns file as download:
- `Content-Type: application/octet-stream`
- `Content-Disposition: attachment; filename="..."`
- Token is **consumed immediately** (deleted before streaming to prevent double-download)

### GET /api/files/view/:token

Returns a full HTML page with inline preview. Token consumed immediately.

## File Type Detection

`detectFileType(filePath)` determines display mode:

1. Check filename: `Dockerfile` → `{ kind: 'code', mode: 'dockerfile' }`
2. Check filename: `Makefile`, `Gemfile` → `{ kind: 'code', mode: 'null' }` (plain text)
3. Check extension: `.md`, `.markdown` → `{ kind: 'markdown', mode: null }`
4. Check extension against `CM_MODES` map → `{ kind: 'code', mode: '...' }`
5. Unknown extension: read first 1KB and check for null bytes
   - Contains `\0` → `{ kind: 'binary', mode: null }`
   - No null bytes → `{ kind: 'code', mode: 'null' }` (plain text, shown in CodeMirror)

## Code Viewer (CodeMirror 5)

### CM_MODES Mapping

| Extensions | Mode |
|-----------|------|
| `js`, `mjs`, `cjs` | `javascript` |
| `jsx` | `jsx` |
| `ts`, `tsx` | `javascript` (CM5 uses TypeScript mode) |
| `json` | `application/json` |
| `css`, `scss`, `less` | `css` |
| `html`, `htm` | `htmlmixed` |
| `xml`, `svg` | `xml` |
| `py`, `pyw` | `python` |
| `sh`, `bash`, `zsh`, `fish` | `shell` |
| `yaml`, `yml` | `yaml` |
| `sql` | `sql` |
| `md`, `markdown` | `markdown` |
| `java`, `c`, `h`, `cpp`, `cc`, `hpp`, `cs`, `kt`, `kts`, `scala` | `clike` |
| `rs` | `rust` |
| `go` | `go` |
| `rb` | `ruby` |
| `php` | `php` |
| `swift` | `swift` |
| `r` | `r` |
| `toml` | `toml` |
| `ini`, `cfg`, `conf` | `properties` |
| `dockerfile` | `dockerfile` |
| `diff`, `patch` | `diff` |

### Mode Dependencies

Some CodeMirror 5 modes are composites and require parent modes loaded first:

```javascript
const MODE_DEPS = {
  htmlmixed: ['xml', 'javascript', 'css'],
  jsx: ['javascript'],
  php: ['clike', 'xml', 'javascript', 'css', 'htmlmixed'],
};
```

Mode scripts are loaded dynamically from CDN (`cdnjs.cloudflare.com/ajax/libs/codemirror/5.65.16/mode/`).

### Viewer UI

Code files display:
- Header bar: filename, syntax badge, Download + Close buttons (client-side Blob download from embedded content)
- Full-height CodeMirror editor: material-darker theme, line numbers, read-only, viewport-aware rendering

## Markdown Viewer

Files with `.md`/`.markdown` extension render using `marked.js` v12.0.0 from CDN. Dark-themed CSS with Catppuccin Mocha colors:
- Header bar: filename, syntax badge, Download + Close buttons (client-side Blob download)
- Headers in `#89b4fa`, code blocks in `#11111b`, inline code in `#f5c2e7`
- Tables, blockquotes, lists fully styled
- Max-width 900px centered layout

## Binary Files

Binary files (detected via null-byte check) show a "Binary file — cannot preview" message with a reference to use the Download button from the chat UI (previous page).

## Viewer Page HTML

`generateViewerPage(filePath, content, title)` produces a complete standalone HTML document. Uses:
- Catppuccin Mocha color scheme (`#1e1e2e` background, `#cdd6f4` text)
- `SF Mono` / `Fira Code` monospace font stack
- Escape-safe content embedding (prevents `</script>` tags from breaking the page)
- Responsive layout with fixed header bar + scrollable content area

## Related

- [index.md](index.md) — Architecture overview
- [http-api.md](http-api.md) — REST API endpoints
- [configuration.md](configuration.md) — Environment variables
