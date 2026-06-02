# Remember Scroll Position on Session Switch

**Created:** 2026-06-02  
**Status:** ✅ Completed

## Goal

When switching from one session to another, remember the scroll position (`scrollTop`) of the session being left. When switching back, restore that position. If no saved position exists for the target session (first view), scroll to the bottom (`scrollTop = scrollTopMax`).

## Context

Currently, `showSession()` resets `_renderedCount = 0`, which triggers a full rebuild in `showSessionContent()`. During the full rebuild, `prevScrollTop` and `prevScrollHeight` are saved from the messages element — but these values belong to the **old** session's content, making the proportional scroll restoration (`prevScrollTop * newHeight / prevHeight`) meaningless on session switch.

Users expect: switch to session B, browse around, switch to session C, switch back to B → view is where they left it.

## Plan

### 1. Add `_scrollTop` field to per-session state

In `showSession()` (before clearing `activeSession`), save `msgsEl.scrollTop` to the outgoing session object:
```js
if (activeSession && sessions.has(activeSession)) {
  sessions.get(activeSession)._scrollTop = msgsEl.scrollTop;
}
```

### 2. Track scroll position in real time via scroll handler

In the `msgsEl.addEventListener('scroll', ...)` handler, update the active session's `_scrollTop` on every scroll event so the value is always current even if no session switch occurs:

```js
if (activeSession && sessions.has(activeSession)) {
  sessions.get(activeSession)._scrollTop = msgsEl.scrollTop;
}
```

### 3. Restore or scroll to bottom in `showSessionContent()`

In the full rebuild branch of `showSessionContent()`, after setting `msgsEl.innerHTML`, replace the proportional scroll logic when `prevCount === 0` (session switch) with:

```js
if (prevCount === 0) {
  // Session switch: restore saved position or scroll to bottom
  if (sess._scrollTop !== undefined && sess._scrollTop > 0) {
    const maxScroll = msgsEl.scrollHeight - msgsEl.clientHeight;
    msgsEl.scrollTop = Math.min(sess._scrollTop, maxScroll);
  } else {
    msgsEl.scrollTop = msgsEl.scrollHeight; // scroll to bottom
  }
}
```

For non-switch rebuilds (`prevCount > 0`), keep the existing proportional scroll restoration as-is.

### 4. Reset `_scrollTop` on session clear

When `clearSessionEvents()` is called, reset `sess._scrollTop = undefined` so it scrolls to bottom on next view (events have changed, old position is invalid).

## Files Affected

- `index.html` — `showSession()` (~L1639), `showSessionContent()` (~L1848), scroll handler (~L5012), `clearSessionEvents()`

## Edge Cases

- **No saved position:** scroll to bottom (scrollTopMax) — handled by `else` branch
- **Saved position exceeds new content height:** clamp via `Math.min(savedTop, maxScroll)`
- **Session cleared/reloaded:** reset `_scrollTop` to force bottom-scroll on next view
- **Streaming updates after switch:** incremental append in the same session continues as normal; `_scrollTop` is updated by the scroll handler in real time
- **Load older events:** `_loadingOlderEvents` anchoring already handled; `_scrollTop` gets updated via scroll handler naturally
- **`_scrollTop` is NOT persisted to localStorage or disk** — it's in-memory only (per-session Map value, lost on page refresh). This is intentional: positions from a previous page load are meaningless after a refresh.
