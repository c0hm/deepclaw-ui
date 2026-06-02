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

// Shared Basic Auth validation — used by both HTTP and WebSocket paths
function validateBasicAuth(authHeader) {
  if (!authHeader || !authHeader.startsWith('Basic ')) return false;
  const base64Credentials = authHeader.split(' ')[1];
  try {
    const credentials = Buffer.from(base64Credentials, 'base64').toString('utf8');
    const [, password] = credentials.split(':');
    return password === DCPASS;
  } catch {
    return false;
  }
}
```

### HTTP Request Handler

```javascript
if (authEnabled) {  // always true
  if (!validateBasicAuth(req.headers['authorization'])) {
    res.writeHead(401, {
      'Content-Type': 'text/plain',
      'WWW-Authenticate': 'Basic realm="DeepClaw UI"'
    });
    res.end('401 Unauthorized');
    return;
  }
}
```

### WebSocket Handler

```javascript
const wss = new WebSocket.Server({
  server,
  verifyClient: ({ req }) => {
    return authEnabled ? validateBasicAuth(req.headers['authorization']) : true;
  }
});
```

**Key notes:**
- Auth validation is shared between HTTP and WebSocket via `validateBasicAuth()`
- `verifyClient` blocks unauthenticated WebSocket upgrades with HTTP 401
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

WebSocket connections (browser ↔ server) are authenticated via the **same Basic Auth check** as HTTP endpoints. The `verifyClient` callback on the WebSocket server validates the `Authorization` header from the HTTP upgrade request.

**Browser behavior:** Browsers automatically include cached Basic Auth credentials on same-origin WebSocket upgrade requests, including auto-reconnects after server restart.

**Password rotation:** When the password changes and the server restarts, existing browser clients are **immediately locked out** — their WebSocket reconnects fail with HTTP 401 because the browser's cached credentials no longer match. Users must refresh the page to re-authenticate with the new password.

## Security Considerations

| Aspect | Note |
|-------|------|
| Transport | Use HTTPS in production (drop `fullchain.pem` + `privkey.pem` in project root) |
| Password | Use strong passwords in production |
| Token | `OPENCLAW_TOKEN` is separate from UI password — used for Gateway auth |
| Auth toggle | Auth **cannot be disabled** — always enforced |
| WebSocket auth | WebSocket connections require same Basic Auth as HTTP — enforced via `verifyClient` |
| Password rotation | Changing `DCPASS` and restarting **immediately revokes** all existing clients; they must re-authenticate |

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
