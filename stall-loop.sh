#!/usr/bin/env bash
# stall-loop.sh - Keep Claude Code thinking = showing ads
#
# Usage:
#   ./stall-loop.sh launch   # Create tmux session + open Claude
#   ./stall-loop.sh start    # Start auto-loop (sends prompt every ~5min)
#   ./stall-loop.sh send     # Manually send a prompt right now
#   ./stall-loop.sh attach   # Watch the ads in real-time
#   ./stall-loop.sh status   # Check if running
#   ./stall-loop.sh stop     # Kill everything

SESSION="stall-ads"
LOG="$HOME/.claude-ad-loop.log"
PIDFILE="/tmp/stall-loop-pid"
PROMPT="Count silently from 1 to 10000. For each number check if it is prime and compute its square root. Only output 'OK [N]' when done."
INTERVAL=${INTERVAL:-310}

mkdir -p "$(dirname "$LOG")"

send_prompt() {
  tmux send-keys -l -t "$SESSION" "$PROMPT"
  sleep 1
  tmux send-keys -t "$SESSION" Enter
}

case "${1:-status}" in
  launch)
    tmux kill-session -t "$SESSION" 2>/dev/null || true
    sleep 1
    tmux new-session -s "$SESSION" "claude"
    ;;

  start)
    if ! tmux has-session -t "$SESSION" 2>/dev/null; then
      echo "ERROR: tmux session '$SESSION' not found. Run '$0 launch' first." | tee -a "$LOG"
      exit 1
    fi

    echo "Sending first prompt..." | tee -a "$LOG"
    send_prompt
    echo "[$(date '+%H:%M:%S')] First prompt sent." | tee -a "$LOG"

    # Background loop
    while true; do
      sleep "$INTERVAL"
      send_prompt
      echo "[$(date '+%H:%M:%S')] Loop prompt sent." | tee -a "$LOG"
    done &
    echo $! > "$PIDFILE"

    echo ""
    echo "============================================"
    echo "  ADS ARE RUNNING"
    echo "  Watch:   tmux attach -t $SESSION"
    echo "  Detach:  Ctrl+B then D"
    echo "  Manual:  $0 send"
    echo "  Stop:    $0 stop"
    echo "============================================"
    ;;

  send)
    if ! tmux has-session -t "$SESSION" 2>/dev/null; then
      echo "ERROR: tmux session '$SESSION' not found." | tee -a "$LOG"
      exit 1
    fi
    send_prompt
    echo "[$(date '+%H:%M:%S')] Prompt sent manually." | tee -a "$LOG"
    ;;

  stop)
    [ -f "$PIDFILE" ] && kill "$(cat "$PIDFILE")" 2>/dev/null; rm -f "$PIDFILE"
    tmux kill-session -t "$SESSION" 2>/dev/null || true
    echo "Stopped." | tee -a "$LOG"
    ;;

  status)
    tmux has-session -t "$SESSION" 2>/dev/null && echo "Session: RUNNING" || echo "Session: STOPPED"
    [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null && echo "Loop: RUNNING (${INTERVAL}s)" || echo "Loop: STOPPED"
    ;;

  attach)
    tmux attach -t "$SESSION"
    ;;

  *)
    echo "Usage: $0 {launch|start|send|attach|status|stop}"
    ;;
esac
