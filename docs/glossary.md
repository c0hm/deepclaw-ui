# Glossary

## Domain Terms

### Agent

An autonomous AI assistant instance in the OpenClaw system that processes user requests.

**Examples:**
- `agent:main` - Main agent for general tasks
- `agent:personal` - Personal agent for private conversations

### Session

A conversation context associated with a specific agent, stored and managed independently.

**Key Format:** `agent:instance:name`

**Example:** `agent:main:main` - Main instance of main agent

### Gateway

The OpenClaw Gateway - central server that routes messages to agents and manages session state.

**Default Port:** 18789

**Protocol:** WebSocket

### DeepClaw UI

The web-based dashboard for monitoring and interacting with the OpenClaw system.

**Default Port:** 1234

### Event

A discrete occurrence in a session's lifecycle.

**Types:**
- `tool_start` - Tool execution began
- `tool_result` - Tool execution completed
- `run_start` - LLM call started
- `run_end` - LLM call completed
- `run_error` - Error occurred
- `assistant_text` - Assistant response
- `user_text` - User message
- `thinking` - Model reasoning

### Token

A unit of text processing in LLMs.

**Types:**
- `inputTokens` - Tokens sent to LLM
- `outputTokens` - Tokens received from LLM
- `totalTokens` - Input + Output
- `contextTokens` - Estimated conversation size

### Tool

A function the agent can call to interact with external systems.

**Examples:**
- `read` - Read file contents
- `write` - Write file contents
- `exec` - Run shell commands

### Stream

A category of events within a session.

**Values:**
- `tool` - Tool execution events
- `lifecycle` - LLM run lifecycle events
- `assistant` - Assistant text deltas
- `user` - User text deltas

### Phase

The current state within a stream.

**Values:**
- `start` - Execution started
- `done` - Execution completed
- `result` - Result available
- `update` - Intermediate update
- `end` - Run ended
- `error` - Error occurred

### Run ID

A unique identifier for a single LLM call or tool execution.

### Session Key

Unique identifier for a session: `agent:instance:name`

### WebSocket

Bidirectional communication protocol for real-time updates.

### REST API

HTTP-based API for session queries and management.

### Basic Auth

HTTP authentication using username/password.

---

## Related Documentation

- [Session Management](session-management.md)
- [Gateway WebSocket API](gateway-websocket.md)
- [HTTP API](http-api.md)