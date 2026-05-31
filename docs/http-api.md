# HTTP REST API

Base: `http://localhost:1234` | Auth: HTTP Basic (password: `DCPASS` env or `deepclaw`)

## Endpoints

| Method | Path | Response |
|--------|------|----------|
| GET | `/` | HTML page |
| GET | `/api/status` | `{ gatewayReady, sessionCount, clientCount, dataDir }` |
| GET | `/api/sessions` | `{ sessions: [{ key, sessionId, eventCount, messageCount, tokens, lastTs }] }` |
| GET | `/api/agents` | `{ agents: [{ id, model }] }` |
| GET | `/api/session/:key` | Full session object (events + messages + tokens + metadata) |
| GET | `/api/events/:key?limit=100` | `{ sessionKey, events[], total }` |
| POST | `/api/session/:key/reset` | `{ key, reset: true }` — clears events/messages, resets tokens, saves |
| POST | `/api/session/:key/delete` | `{ key, deleted: true }` — removes from memory + disk |

All endpoints include `Access-Control-Allow-Origin: *`.

## Auth (Basic)

```bash
curl -u :password http://localhost:1234/api/status
# Empty username, password is DCPASS or "deepclaw"
```

## Related

- [index.md](index.md) — Overview
- [authentication.md](authentication.md) — Auth details
