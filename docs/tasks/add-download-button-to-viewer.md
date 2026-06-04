# Add Download Button to File Viewer Tabs

**Date:** 2026-05-31
**Status:** Complete

## Problem

The file viewer tabs (opened via clicking file paths in chat) had no Download button. Users viewing a code or markdown file in the standalone viewer page had no way to download it — they had to go back to the chat UI and use the download link there.

The CSS for `.dl` (download button) already existed in the viewer page styles, and the docs incorrectly claimed "Download + Close buttons" were present.

## Solution

Added a client-side Download button to the viewer page header bar for both code and markdown file viewers. The download uses the file content already embedded in the page, creating a Blob and triggering a browser download via a temporary `<a>` element click — no additional server request needed.

### Changes

**`miniclaw-ui.js` — `generateViewerPage()` (L316-L385):**

1. **Markdown viewer:** Added `<button class="dl" onclick="downloadFile()">⬇ Download</button>` to header bar + `<script>` block defining `downloadFile()` with content embedded as `window.__FC__`

2. **Code viewer:** Same Download button + script block added to header bar

3. Download function creates a Blob from `window.__FC__` (embedded content), generates an object URL, and triggers a download via programmatic `<a>` click

4. Binary files: No download button added — the utf-8 decoded content would be corrupt for binary files. Existing message directs users to the chat UI's download button.

**`docs/file-sharing.md`:**
- Updated code viewer UI section to note "client-side Blob download from embedded content"
- Updated markdown viewer section to mention Download button
- Updated binary files section wording for clarity

## Technical Notes

- Content is already embedded in the page as a JS variable (passed to CodeMirror or marked.js)
- No extra network request needed — download is instant
- Token is already consumed when the viewer page loads, so server-side download via the original token is impossible
- Uses `application/octet-stream` MIME type for universal download compatibility
