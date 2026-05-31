# Troubleshooting

## Connection

| Symptom | Cause | Fix |
|---------|-------|-----|
| "Connecting to gateway..." stuck | Gateway not on 18789 | Verify Gateway running; check `GW_WSS=true` if TLS |
| WS connection error | Server not running | `node deepclaw-ui.js`; refresh page |
| Sessions list empty | No sessions exist | Send a message or click "Test Traffic" |

## Auth

| Symptom | Fix |
|---------|-----|
| 401 Unauthorized | Password is `DCPASS` env value, or `deepclaw` if unset |
| Repeated prompts | Clear cached credentials; try `DCPASS=` restart |

## Sessions

| Symptom | Fix |
|---------|-----|
| 0 events | Click session to trigger history fetch |
| Missing data | Check browser console → Network tab → API responses |
| Corrupted session | `rm data/session-{key}.json` |
| Missing data dir | `mkdir data`; restart server |

## UI

| Symptom | Fix |
|---------|-----|
| Blank page | Check URL `http://localhost:1234/`; verify `index.html` exists |
| Sidebar stuck | Refresh page; resize to desktop |
| Scroll frozen | Click "↓ New messages" button; clear filters |
| "New messages" button stuck | Scroll to bottom manually |

## Performance

| Issue | Fix |
|-------|-----|
| Slow / laggy | `rm data/*.json` (old sessions); restart server |
| High memory | Run `> gc` CLI; delete old session files |
| Server crash | Reduce stored events (edit source `MAX_EVENTS`) |

## Debug

```bash
# Check API
curl http://localhost:1234/api/status
curl http://localhost:1234/api/sessions

# Check Gateway
curl http://localhost:18789/api/status  # if Gateway serves HTTP

# Browser DevTools (F12)
# Network tab → filter WS → inspect messages
# Console tab → JS errors
```

## Reset Everything

```bash
rm -rf data/*.json
# or from CLI:
> reset   # clears memory
> gc      # removes stale sessions
```
