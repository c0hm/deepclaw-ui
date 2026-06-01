# Fix: New session sidebar stuck in "Creating..." status

**Date:** 2026-06-01
**Status:** Fixed

## Problem

After creating a new session via the "Start New Session" modal dialog, the
session creates successfully and messages can be sent, but the sidebar
shows "Creating..." permanently.

## Root Cause

The `sessions.changed` event (with `reason: 'create'`) arrives and properly
clears `sess._optimistic = false` in the `handleGatewayMsg` handler. However,
`handleGatewayMsg` then falls through to `scheduleUIUpdate()` (via the WS
`onmessage` handler) with **no force flags**.

In `updateUI()`, the condition for calling `refreshSessionList()` is:

```js
if (forceList || sessions.size !== _lastSessionCount) {
    _lastSessionCount = sessions.size;
    refreshSessionList();
}
```

`_lastSessionCount` was already set to `sessions.size` when `createNewSession()`
first called `scheduleUIUpdate(true)` after adding the optimistic session.
Since `sessions.size` doesn't change when `_optimistic` is cleared, the
sidebar **never re-renders** after the gateway confirms creation.

### Flow

1. `createNewSession()` → adds optimistic session → `_lastSessionCount = -1` → `scheduleUIUpdate(true)` → sidebar renders "Creating..."
2. `sessions.changed` (create) arrives → `sess._optimistic = false`
3. `scheduleUIUpdate()` (no force) → `_lastSessionCount === sessions.size` → **no sidebar re-render**
4. Sidebar stuck showing "Creating..."

## Fix

Added `_lastSessionCount = -1` in the `sessions.changed` handler when the
`_optimistic` flag is cleared. This forces `refreshSessionList()` on the
next UI update pass, immediately updating the sidebar to remove the
"Creating..." status.

**File:** `index.html`, line ~1226

```js
if (sess._optimistic) {
    sess._optimistic = false;
    sess.lastTs = new Date();
    _lastSessionCount = -1; // force sidebar re-render
}
```

This follows the existing pattern used in `createNewSession()` at line 3309.
