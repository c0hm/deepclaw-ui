# Show exec Command in tr-detail

**Date:** 2026-06-02
**Status:** done

## Problem

The `exec` tool result currently only shows the command inside the `.tr-body` (hidden by default). Users need to expand every exec result to see which command was run. The command should be visible in the `.tr-detail` area of the `.tr-header` so it's always visible.

## Desired Behavior

- **Compact (collapsed):** Show the command in `tr-detail`, truncated to 2 lines via CSS line-clamp
- **Expanded:** Show the full command (unclamped `tr-detail` + existing `tr-cmd` in body)
- **Command highlighting:** Command name (first word) rendered in distinct style from arguments
- **File paths clickable:** Detect paths in arguments and make them previewable via `viewFile()`

## Session-Only Path Blacklist

When a user clicks a file link that doesn't exist, instead of showing an alert:
1. The link is silently removed — the `.file-link` span is replaced with a plain text node
2. The path is added to `_blacklistedPaths` Set (line 514)
3. On re-render, `renderExecCommand` skips blacklisted paths (line 2200)
4. Blacklist is per-session only (not persisted to localStorage)

### `previewFileLink(el, filePath)` (line 2631)
New function that wraps `viewFile` logic. On fetch failure:
- Logs a `console.warn` (not `alert`)
- Adds path to `_blacklistedPaths`
- Replaces the clicked `<span class="file-link">` with a `document.createTextNode`

## Implementation

### CSS (lines 178-181)
- `.cmd-name` — white bold text for the command binary name
- `.tr-detail .cmd-name` — accent-colored within the header's muted detail line
- `.file-link` — info-colored underlined clickable paths with hover state

### CSS (line 168)
- `.tr-expanded .tr-header .tr-detail { -webkit-line-clamp: unset; }` — removes 2-line clamp when expanded

### JS `renderExecCommand(cmd)` (line 2183)
New helper function that:
1. Splits the command string into command name + arguments on first space
2. Wraps the command name in `<span class="cmd-name">`
3. Scans arguments with regex for file paths (`/...`, `~/...`, `./...`, `../...`)
4. Wraps detected paths in clickable `<span class="file-link">` with `viewFile()` onclick
5. Skips URLs (matches preceded by `:` or containing `://`) and very short paths

### JS `renderExecHeader` (lines 2233, 2244)
- Header `tr-detail`: `'$ ' + renderExecCommand(cmd)` instead of `'<b>$</b> ' + escHtml(cmd)`
- Body `tr-cmd`: `'$ ' + renderExecCommand(cmd)` instead of `'$ <b>' + escHtml(cmd) + '</b>'`

## Path Regex
```
/((?:~|\.\.?)?\/(?:[^\s"'`;|&<>()\[\]{}:]+\/?)+)/g
```
Matches: absolute, home-relative, and dot-relative paths. Excludes `:` to avoid matching URL schemes and Docker volume mounts.

## Behavior Summary

| State | Header `tr-detail` | Body |
|-------|-------------------|------|
| Compact | `↳ exec  exit 0  $ **git** status /path/to/file  2.5s · ~/cwd` (≤2 lines) | Hidden |
| Expanded | Full command unclamped | Full command + output |
