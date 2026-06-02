# Previous Messages Scroll Button

**Created:** 2026-06-02
**Status:** ✅ Completed

## Goal

Add a "↑ N messages to user" button at the TOP of the messages panel that jumps to the previous user message — not just to the top.

## Motivation

When the user scrolls UP (away from bottom), the "↓ New messages" button appears at the bottom. But there's no symmetrical navigation aid when the user scrolls DOWN (away from top). The user wants to quickly jump back to the previous user message ("what did I ask?") without hunting through the scroll.

## Design

- **State variable:** `userScrolledDown` (boolean) — whether user has scrolled away from the top of messages
- **Button:** `<button id="prev-msg-btn">` positioned absolutely in `#content`, aligned with the top of `#messages`
- **Scroll detection:** `msgsEl.scrollTop >= 80` → `userScrolledDown = true`
- **Button click:** `jumpToPrevUser()` — finds the closest `.msg-user` / `.compact-user` element above the viewport and smooth-scrolls to it
- **Fallback:** If no user message is above the viewport, scrolls to top
- **Button text:**
  - `"↑ N messages to user"` — when a previous user message exists, counting visible elements between viewport and that message
  - `"↑ Jump to user message"` — when the previous user message is the very next element above
  - `"↑ Jump to top"` — fallback when no user message is found above

## Changes

1. `index.html`:
   - Add `userScrolledDown` state variable
   - Add `#prev-msg-btn` HTML element (in `#content`, before `#messages`)
   - Add CSS for `#prev-msg-btn` (mirrors `#new-msg-btn`)
   - Update scroll handler to detect scrolled-away-from-top
   - Add `jumpToPrevUser()` function (smart-scroll to previous user message)
   - Add `findPreviousUserEl()` function (scans DOM for `.msg-user` / `.compact-user` above viewport)
   - Add `updatePrevMsgButton()` function with dynamic top positioning and smart text
   - Add `countMessagesToPrevUser()` helper (counts elements from viewport to target user message)
   - In `showSessionContent`, call `updatePrevMsgButton()` after render

2. `docs/ui-components.md`:
   - Document new button, state variable, and functions
