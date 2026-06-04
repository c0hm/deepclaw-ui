#!/bin/bash
# MiniClaw UI installer — interactive setup + systemd user service
set -e

cd "$(dirname "$0")"
SCRIPT_DIR="$(pwd)"

echo "═══════════════════════════════════════════"
echo "  🐚 MiniClaw UI Installer"
echo "═══════════════════════════════════════════"
echo ""

# ── Port ──────────────────────────────────────
read -r -p "Port [1234]: " PORT
PORT="${PORT:-1234}"

# ── Password ──────────────────────────────────
read -r -p "Dashboard password [miniclaw]: " MCPASS
MCPASS="${MCPASS:-miniclaw}"

# ── WSS (optional) ────────────────────────────
read -r -p "Use WSS for gateway connection? (y/N): " WSS_ANS
if [[ "$WSS_ANS" =~ ^[Yy]$ ]]; then
  GW_WSS="true"
else
  GW_WSS="false"
fi

echo ""
echo "───────────────────────────────────────────"
echo "  Port:        $PORT"
echo "  Password:    $MCPASS"
echo "  Gateway WSS: $GW_WSS"
echo "  Directory:   $SCRIPT_DIR"
echo "───────────────────────────────────────────"
echo ""

# ── Confirm ───────────────────────────────────
read -r -p "Proceed with install? (Y/n): " CONFIRM
if [[ ! "$CONFIRM" =~ ^[Yy]?$ ]]; then
  echo "Aborted."
  exit 0
fi

# ── Install npm dependencies ──────────────────
echo ""
echo "📦 Installing npm dependencies…"
npm install --production

# ── Update restart.sh ─────────────────────────
echo "📝 Updating restart.sh…"
cat > "$SCRIPT_DIR/restart.sh" <<RESTART
#!/bin/bash
# Restart miniclaw-ui with current environment variables

cd "$SCRIPT_DIR"

# Kill existing process
pkill -f "node.*miniclaw-ui.js" 2>/dev/null
sleep 1

# Start with configured env vars
PORT="${PORT}" \\
MCPASS="${MCPASS}" \\
GW_WSS="${GW_WSS}" \\
node miniclaw-ui.js
RESTART
chmod +x "$SCRIPT_DIR/restart.sh"

# ── Create systemd user service ───────────────
echo "📝 Creating systemd user service…"
mkdir -p "$HOME/.config/systemd/user"

cat > "$HOME/.config/systemd/user/miniclaw-ui.service" <<UNIT
[Unit]
Description=MiniClaw UI Dashboard
After=network-online.target openclaw-gateway.service
Wants=network-online.target openclaw-gateway.service

[Service]
ExecStart=/usr/bin/node $SCRIPT_DIR/miniclaw-ui.js
WorkingDirectory=$SCRIPT_DIR
Restart=always
RestartSec=5
TimeoutStopSec=10
TimeoutStartSec=30

Environment=PORT=$PORT
Environment=MCPASS=$MCPASS
Environment=GW_WSS=$GW_WSS
Environment=HOME=$HOME
Environment=PATH=/usr/bin:$HOME/.local/bin:$HOME/.npm-global/bin:/usr/local/bin

[Install]
WantedBy=default.target
UNIT

# ── Enable & start ────────────────────────────
echo "🔧 Reloading systemd, enabling & starting…"
systemctl --user daemon-reload
systemctl --user enable --now miniclaw-ui

echo ""
echo "═══════════════════════════════════════════"
echo "  ✅ MiniClaw UI installed!"
echo ""
echo "  Dashboard:  http://localhost:$PORT"
echo "  Password:   $MCPASS"
echo "  Service:    systemctl --user status miniclaw-ui"
echo "  Logs:       journalctl --user -u miniclaw-ui -f"
echo "═══════════════════════════════════════════"
