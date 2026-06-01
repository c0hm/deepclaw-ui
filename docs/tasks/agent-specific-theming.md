# Agent-Specific Theming

**Date:** 2026-05-31
**Status:** completed

## Goal

Subtly change the UI accent color based on which agent's session is active. Each agent gets a deterministic, persistent accent color that shifts the `--accent` CSS variable hue while keeping saturation and lightness fixed.

## Design

- Only `--accent` CSS variable changes (hue shift only)
- Deterministic color generation via djb2 hash of agent name → hue in range 225-255°
- localStorage stores `{agentName: {hue}}` map under key `deepclaw-ui-agent-themes`
- Applied on session switch (both `showSession()` and new session creation)
- Cleared when no session is active
- Restored on page load if `_lastActiveSession` exists

## Changes

### index.html

1. **New Section 2b** — Agent theme functions (after prefs, before rAF throttle):
   - `_AGENT_THEMES_KEY = 'deepclaw-ui-agent-themes'`
   - `hashAgentName(name)` — djb2 hash
   - `agentHueFromName(name)` — hash → hue in 225-255
   - `loadAgentThemes()` / `saveAgentThemes(themes)` — localStorage persistence
   - `getAgentName(sk)` — extract agent from session key (e.g. `agent:main:main` → `main`)
   - `getOrCreateAgentTheme(agentName)` — lookup or generate
   - `applyAgentTheme(agentName)` — set `--accent` CSS var via `document.documentElement.style.setProperty`
   - `clearAgentTheme()` — remove `--accent` override via `document.documentElement.style.removeProperty`

2. **Startup restoration** — in `_applyPrefs` IIFE: if `_lastActiveSession` exists, apply theme

3. **`showSession(sk)`** — `applyAgentTheme(getAgentName(sk))` after `activeSession = sk`

4. **New session creation** — `applyAgentTheme(getAgentName(sessionKey))` + `savePrefs()` after `activeSession = sessionKey`

5. **Session clearing** — `clearAgentTheme()` added at all 4 `activeSession = null` points:
   - `sessions.changed` deletion handler
   - "no sessions" fallback in rendering
   - `deleteSession` fetch callback
   - New session creation timeout/failure
