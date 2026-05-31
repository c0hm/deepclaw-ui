# Authentication

## Overview

DeepClaw UI requires HTTP Basic Authentication on **all** HTTP endpoints. Auth is **always enabled** and cannot be disabled.

## Password

Set the `DCPASS` environment variable to change the password:

```bash
# Custom password
DCPASS=mypassword node deepclaw-ui.js
```

**Default password:** `deepclaw` (when `DCPASS` not set or empty):

```bash
# Uses default password "deepclaw"
node deepclaw-ui.js
```

## How It Works

### Server-Side

```javascript
const DCPASS = process.env.DCPASS || 'deepclaw';  // default is 'deepclaw'
const authEnabled = true;  // always enabled, unconditionally
```

### Request Handler

```javascript
if (authEnabled) {  // always true
  const authHeader = req.headers['authorization'];
  if (!authHeader || !authHeader.startsWith('Basic ')) {
    res.writeHead(401, {
      'Content-Type': 'text/plain',
      'WWW-Authenticate': 'Basic realm="DeepClaw UI"'
    });
    res.end('401 Unauthorized');
    return;
  }

  const base64Credentials = authHeader.split(' ')[1];
  const credentials = Buffer.from(base64Credentials, 'base64').toString('utf8');
  const [username, password] = credentials.split(':');
  const validPass = DCPASS;  // no fallback logic

  if (password !== validPass) {
    res.writeHead(401, {
      'Content-Type': 'text/plain',
      'WWW-Authenticate': 'Basic realm="DeepClaw UI"'
    });
    res.end('401 Unauthorized');
    return;
  }
}
```

**Key notes:**
- `validPass = DCPASS` — no `DEFAULT_PASSWORD` fallback constant exists in code
- `authEnabled = true` — always on, not conditional on `DCPASS` being set
- Default password is inline in the `DCPASS` declaration: `process.env.DCPASS || 'deepclaw'`

## Client-Side

### Using curl

```bash
# With default password
curl -u :deepclaw http://localhost:1234/api/status

# With custom password
curl -u :mypassword http://localhost:1234/api/status
```

### Browser

Browser will prompt for credentials automatically when accessing protected endpoints. The `username` field can be anything — only the password is checked.

## WebSocket

WebSocket connections (browser ↔ server) do **not** use HTTP Basic Auth. Auth is applied only to HTTP endpoints. The browser WebSocket is intended for use after the browser has already authenticated via the HTTP endpoint (loaded `index.html`).

## Security Considerations

| Aspect | Note |
|-------|------|
| Transport | Use HTTPS in production (drop `fullchain.pem` + `privkey.pem` in project root) |
| Password | Use strong passwords in production |
| Token | `OPENCLAW_TOKEN` is separate from UI password — used for Gateway auth |
| Auth toggle | Auth **cannot be disabled** — always enforced |

## API Keys vs Password

- **UI Password** (`DCPASS`): Protects the web UI and REST API
- **Gateway Token** (`OPENCLAW_TOKEN` or `~/.openclaw/openclaw.json`): Authenticates to OpenClaw Gateway via `auth.token` in connect params. When device identity files are missing, the UI falls back to **token-only auth** (no device signing required).
- **Device Token** (`operatorToken`): Loaded from `device-auth.json`, sent as `auth.deviceToken` in connect params

All three can be used together:

```bash
OPENCLAW_TOKEN=gw_token DCPASS=ui_pass node deepclaw-ui.js
```

## Related Documentation

- [Configuration](configuration.md)
- [HTTP API](http-api.md)
- [Gateway WebSocket](gateway-websocket.md)
