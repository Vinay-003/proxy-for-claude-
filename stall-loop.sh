#!/usr/bin/env bash
# stall-loop.sh - Send prompts to Claude Code in tmux
#
# Usage:
#   ./stall-loop.sh launch   # Open Claude in tmux (attach to watch)
#   ./stall-loop.sh start    # Send first prompt + start auto-loop
#   ./stall-loop.sh send     # Send one prompt now
#   ./stall-loop.sh attach   # Re-attach to tmux
#   ./stall-loop.sh stop     # Kill everything

SESSION="stall-ads"
LOG="$HOME/.claude-ad-loop.log"
PIDFILE="/tmp/stall-loop-pid"
PROMPT="Count silently from 1 to 10000. For each number check if it is prime and compute its square root. Only output 'OK [N]' when done."
STALL=${STALL_SECONDS:-300}
INTERVAL=$(( STALL + 30 ))

mkdir -p "$(dirname "$LOG")"

kill_old_loops() {
  [ -f "$PIDFILE" ] && kill "$(cat "$PIDFILE")" 2>/dev/null; rm -f "$PIDFILE"
  sleep 1
}

send_prompt() {
  tmux send-keys -l -t "$SESSION" "$PROMPT"
  sleep 0.5
  tmux send-keys -t "$SESSION" Enter
}

case "${1:-status}" in
  launch)
    kill_old_loops
    tmux kill-session -t "$SESSION" 2>/dev/null || true
    sleep 1
    tmux new-session -d -s "$SESSION" "claude"
    tmux attach -t "$SESSION"
    ;;

  start)
    if ! tmux has-session -t "$SESSION" 2>/dev/null; then
      echo "ERROR: No tmux session. Run '$0 launch' first."
      exit 1
    fi
    kill_old_loops

    echo "[$(date '+%H:%M:%S')] Sending first prompt..." | tee -a "$LOG"
    send_prompt
    echo "[$(date '+%H:%M:%S')] First prompt sent. Loop every ${INTERVAL}s." | tee -a "$LOG"

    while true; do
      sleep "$INTERVAL"
      send_prompt
      echo "[$(date '+%H:%M:%S')] Next prompt sent." | tee -a "$LOG"
    done &
    echo $! > "$PIDFILE"

    echo ""
    echo "Loop running. Watch: tmux attach -t $SESSION"
    echo "Stop: $0 stop"
    ;;

  send)
    if ! tmux has-session -t "$SESSION" 2>/dev/null; then
      echo "ERROR: No tmux session."
      exit 1
    fi
    send_prompt
    echo "[$(date '+%H:%M:%S')] Prompt sent."
    ;;

  stop)
    kill_old_loops
    tmux kill-session -t "$SESSION" 2>/dev/null
    echo "Stopped."
    ;;

  status)
    tmux has-session -t "$SESSION" 2>/dev/null && echo "Session: RUNNING" || echo "Session: STOPPED"
    [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null && echo "Loop: RUNNING" || echo "Loop: STOPPED"
    ;;

  attach)
    tmux attach -t "$SESSION"
    ;;

  *)
    echo "Usage: $0 {launch|start|send|attach|status|stop}"
    ;;
esac
