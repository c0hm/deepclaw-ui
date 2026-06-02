# Udiff Format for read/write Tool Results + Actions Inside .udiff-file

**Date:** 2026-06-02
**Status:** completed

## Request

1. Make `tool_result` for `read`/`write` render in the same `.udiff` container format as `edit` when expanded
2. Move `tr-actions` (Copy + JSON buttons) to inside `.udiff-file` on the right side

## Changes

### CSS

- `.udiff-file`: make `display: flex; justify-content: space-between; align-items: center;`
- `.udiff-file .tr-actions`: override `margin-top: 0;`

### New Helpers

- `trActionsHtml(idx)` — returns standard Copy + JSON buttons
- `renderUdiffContent(content, filePath, idx)` — renders file content lines as `.udiff-ctx` with `.udiff-file` header containing tr-actions on right

### Modified Functions

- `renderUnifiedDiff(patchText, filePath, idx)` — when `idx` + `filePath` provided, inject tr-actions into `.udiff-file`
- `renderReadHeader` — use `renderUdiffContent` instead of `renderCodeBlock`, actions in `.udiff-file`
- `renderWriteHeader` — add `.tr-body` with `renderUdiffContent` (looks up tool call for content), actions in `.udiff-file`
- `renderEditHeader` — pass `idx` to `renderUnifiedDiff`, conditionally omit separate tr-actions when patch present
- `renderMemorySearchHeader` — refactor to use `trActionsHtml`
- `renderUpdatePlanHeader` — refactor to use `trActionsHtml`
- `renderExecHeader` — refactor to use `trActionsHtml`
- `renderToolBody` — refactor to use `trActionsHtml`
