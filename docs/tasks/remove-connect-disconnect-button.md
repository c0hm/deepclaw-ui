# Remove Connect/Disconnect Button

**Date:** 2026-06-02  
**Status:** Completed

## Goal

Remove the Connect/Disconnect manual toggle button from the header. Go back to "always connected or retry" mode — auto-connect on page load, auto-retry on disconnect.

## Changes

### HTML Header
- Remove `<button id="connect-btn">` element
- Keep status dot and text (`#dot` + `#conn-status`) for connection status display

### JavaScript
- Remove `_manualDisconnect` variable
- Remove `disconnect()` function
- Remove `toggleConnection()` function
- Modify `connect()`:
  - Remove all button manipulation (`btn.textContent`, `btn.disabled`, `btn.onclick`)
  - Always set auto-retry on close (no `_manualDisconnect` check)
- Call `connect()` on page load (uncomment the init call at bottom)

### Files Modified
- `index.html` — header HTML + connection functions + init
