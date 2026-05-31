# DeepClaw UI

A real-time web dashboard for monitoring and interacting with the OpenClaw Gateway. Watch agent sessions, inspect tool calls and LLM responses, track token usage, and chat with agents — all from a browser.

## Features

- **Real-time Session Monitoring** — Watch events as they happen
- **Tool Call Inspection** — See tool starts, results, and errors
- **LLM Response Tracking** — View thinking traces and assistant responses
- **Token Analytics** — Track input/output tokens and estimated costs
- **Send Messages** — Chat with agents directly from the UI
- **Session Management** — Create, reset, and delete sessions
- **Filtering** — Filter by event type (LLM, Tools, Errors)
- **Optional Password Protection** — Basic Auth support

## Quick Start

```bash
# Install dependencies
npm install

# Run the server
node deepclaw-ui.js

# Open in browser
http://localhost:1234
```

## Configuration

| Variable | Default | Description |
|---------|---------|-------------|
| `PORT` | 1234 | Server port |
| `OPENCLAW_TOKEN` | — | Gateway auth token |
| `DCPASS` | — | UI password |
| `DATA_DIR` | ./data | Session storage |

```bash
# Custom port
PORT=18804 node deepclaw-ui.js

# With password protection
DCPASS=mypassword node deepclaw-ui.js
```

## API

- `GET /` — UI page
- `GET /api/status` — Server status
- `GET /api/sessions` — List sessions
- `GET /api/session/:key` — Get session data
- `POST /api/session/:key/reset` — Reset session
- `POST /api/session/:key/delete` — Delete session

## Tech Stack

- **Backend:** Node.js + ws (WebSocket)
- **Frontend:** Vanilla JavaScript SPA
- **Storage:** JSON files

## Project Structure

```
deepclaw-ui.js   # Backend server
index.html     # Frontend UI
docs/          # Full documentation
data/          # Session storage (auto-created)
```

## Documentation

See the `/docs` folder for detailed documentation:
- [Architecture](docs/index.md)
- [Gateway Integration](docs/gateway-websocket.md)
- [Session Management](docs/session-management.md)
- [HTTP API](docs/http-api.md)
- [Troubleshooting](docs/troubleshooting.md)

## CLI Commands

When running interactively:

- `status` — Show server status
- `sessions` — List sessions
- `events` — Show recent events
- `gc` — Clean up stale sessions
- `reset` — Clear all sessions
- `help` — Show commands