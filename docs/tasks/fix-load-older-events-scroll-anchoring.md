# Fix "Load Older Events" Scroll Anchoring

**Status:** completed  
**Started:** 2026-06-02  
**Completed:** 2026-06-02

## Goal

When clicking "⬆ Load older events", new events are prepended at the top of the event list. The scroll position should anchor so the visible content doesn't move — new content appears above without shifting the user's view.

## Problem

The current `showSessionContent()` uses **proportional scroll preservation** for all full rebuilds:

```js
msgsEl.scrollTop = Math.round(prevScrollTop * msgsEl.scrollHeight / prevScrollHeight);
```

When `prevScrollTop === 0` (user at the very top), this formula gives `newScrollTop = 0`. But the content above the viewport has grown because new older events were prepended. The user sees different (newer) content than before — they've effectively scrolled up without meaning to.

At any non-zero scroll position, proportional scaling also gives wrong results because it assumes content was added uniformly throughout the document, not just at the top.

## Fix

Use **anchor-to-content** scroll logic specifically when loading older events:

```
newScrollTop = oldScrollTop + (newScrollHeight - oldScrollHeight)
```

This keeps the same content at the same visual position regardless of scrollTop value. New content appears above without shifting the view.

### Implementation

1. Added `_loadingOlderEvents` flag in global state (line 520)
2. Set it in `loadMoreEvents()` before calling `showSessionContent()` (line 1759)
3. In `showSessionContent()` full rebuild path, check the flag to choose between anchor-to-content and proportional scroll logic (lines 1952-1958)

### Outcome

When clicking "⬆ Load older events":
- Old behavior: `scrollTop = prevScrollTop * newHeight / oldHeight` — at scrollTop=0 this stayed at 0, shifting visible content
- New behavior: `scrollTop = prevScrollTop + (newHeight - oldHeight)` — compensates exactly for the height added at top, keeping visible content anchored in place
