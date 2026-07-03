#!/usr/bin/env bash
# toggle-model.sh - switch between aerolink and opencode free models
#   STALL_SECONDS=300 ./toggle-model.sh start   (5 min stall per request)
set -e
SETTINGS="$HOME/.claude/settings.json"
STALL=${STALL_SECONDS:-0}

case "${1:-status}" in
  free|proxy)
    sed -i 's|https://capi.aerolink.lat/|http://127.0.0.1:5454/|' "$SETTINGS"
    echo "→ Switched to FREE models via proxy (http://127.0.0.1:5454)"
    echo "  Models: deepseek-v4-flash-free, big-pickle, mimo-v2.5-free, nemotron-3-ultra-free, north-mini-code-free"
    ;;
  aerolink|normal)
    sed -i 's|http://127.0.0.1:5454/|https://capi.aerolink.lat/|' "$SETTINGS"
    echo "→ Switched to AEROLINK models"
    echo "  Models: claude-sonnet-5, claude-opus-4-8, claude-haiku-4-5"
    ;;
  start)
    cd /home/mylappy/Projects/opencode-proxy
    nohup env STALL_SECONDS="$STALL" node proxy.js > /tmp/opencode-proxy.log 2>&1 &
    echo "→ Proxy started (PID: $!)"
    if [ "$STALL" -gt 0 ]; then
      echo "  Stall mode: ${STALL}s ±${STALL_JITTER:-60}s jitter per request"
    fi
    sleep 1
    curl -s http://127.0.0.1:5454/v1/models | python3 -c "import json,sys; d=json.load(sys.stdin); print(f'  {len(d[\"data\"])} models available')"
    ;;
  stop)
    pkill -f "node.*proxy.js" 2>/dev/null || true
    echo "→ Proxy stopped"
    ;;
  status)
    if pgrep -f "node.*proxy.js" > /dev/null 2>&1; then
      echo "Proxy: RUNNING (PID: $(pgrep -f 'node.*proxy.js'))"
    else
      echo "Proxy: STOPPED"
    fi
    if grep -q "127.0.0.1:5454" "$SETTINGS" 2>/dev/null; then
      echo "Claude Code: using FREE models (proxy)"
    else
      echo "Claude Code: using AEROLINK models"
    fi
    ;;
  *)
    echo "Usage: $0 {free|aerolink|start|stop|status}"
    echo ""
    echo "Stall mode (keep spinner running for ads):"
    echo "  STALL_SECONDS=180 $0 start"
    echo "  $0 stop"
    ;;
esac
