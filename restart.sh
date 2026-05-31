#!/bin/bash
# Restart deepclaw-ui with current environment variables

cd /home/ju/deepclaw-ui

# Kill existing process
pkill -f "node.*deepclaw-ui.js" 2>/dev/null
sleep 1

# Start with preserved env vars
PORT="${PORT:-1234}" \
DCPASS="${DCPASS:-deepclaw}" \
GW_WSS="${GW_WSS:-false}" \
node deepclaw-ui.js
