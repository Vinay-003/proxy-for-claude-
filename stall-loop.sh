#!/usr/bin/env bash
# stall-loop.sh - Keep Claude Code thinking = showing ads
#
# How it works:
# 1. Proxy stalls responses by sending fake "thinking" blocks for N minutes
# 2. Claude Code shows the spinner = Kickbacks ads run the whole time
# 3. When Claude finally gets the response, this script sends a new prompt
# 4. The proxy stalls again. Loop forever.
#
# Usage:
#   ./stall-loop.sh start     # Launch Claude in tmux, start the loop
#   ./stall-loop.sh stop      # Kill everything
#   ./stall-loop.sh status    # Check if running
#   ./stall-loop.sh attach    # Watch the ads in real-time

set -euo pipefail
SESSION="stall-ads"
LOG="$HOME/.claude-ad-loop.log"
INTERVAL=${INTERVAL:-310}  # 5 min stall + ~10s response time = 310s

mkdir -p "$(dirname "$LOG")"

case "${1:-status}" in
  start)
    # Kill any existing session
    tmux kill-session -t "$SESSION" 2>/dev/null || true
    sleep 1

    echo "Starting Stall Loop..." | tee -a "$LOG"
    echo "Proxy will stall responses for 5 minutes per prompt." | tee -a "$LOG"

    # Launch Claude in tmux
    tmux new-session -d -s "$SESSION" "claude"
    echo "Waiting for Claude to start..." | tee -a "$LOG"
    sleep 5

    # Send the first prompt immediately
    FIRST_PROMPT="Count silently from 1 to 10000. For each number compute its square root to 10 decimal places. Only output 'OK [N]' when done. Do not show any work."
    tmux send-keys -t "$SESSION" "$FIRST_PROMPT" Enter
    echo "[$(date '+%H:%M:%S')] First prompt sent." | tee -a "$LOG"

    # Background loop: send a new prompt every INTERVAL seconds
    (
      while true; do
        sleep "$INTERVAL"
        PROMPT="Count silently from 1 to 10000. For each number check if it is prime and compute its square root. Only output 'OK [N]' when done."
        tmux send-keys -t "$SESSION" "$PROMPT" Enter 2>/dev/null || true
        echo "[$(date '+%H:%M:%S')] Prompt sent." | tee -a "$LOG"
      done
    ) &
    LOOP_PID=$!
    echo "$LOOP_PID" > /tmp/stall-loop-pid
    echo "Loop PID: $LOOP_PID" | tee -a "$LOG"

    echo ""
    echo "=== Ads are running! ==="
    echo "Attach: tmux attach -t $SESSION"
    echo "Detach: Ctrl+B then D"
    echo "Stop:   $0 stop"
    ;;

  stop)
    if [ -f /tmp/stall-loop-pid ]; then
      kill "$(cat /tmp/stall-loop-pid)" 2>/dev/null || true
      rm -f /tmp/stall-loop-pid
    fi
    tmux kill-session -t "$SESSION" 2>/dev/null || true
    echo "Stopped." | tee -a "$LOG"
    ;;

  status)
    if tmux has-session -t "$SESSION" 2>/dev/null; then
      echo "Stall Loop: RUNNING"
      echo "Attach: tmux attach -t $SESSION"
    else
      echo "Stall Loop: STOPPED"
    fi
    if [ -f /tmp/stall-loop-pid ] && kill -0 "$(cat /tmp/stall-loop-pid)" 2>/dev/null; then
      echo "Auto-loop: RUNNING"
    else
      echo "Auto-loop: STOPPED"
    fi
    ;;

  attach)
    tmux attach -t "$SESSION"
    ;;

  *)
    echo "Usage: $0 {start|stop|status|attach}"
    echo ""
    echo "Prerequisites:"
    echo "  1. Start proxy with stall: STALL_SECONDS=300 ./toggle-model.sh start"
    echo "  2. Switch to free mode:     ./toggle-model.sh free"
    echo "  3. Run this loop:           $0 start"
    echo ""
    echo "Commands:"
    echo "  start    Launch Claude in tmux and start the auto-loop"
    echo "  stop     Kill the tmux session and loop"
    echo "  status   Check if running"
    echo "  attach   Watch the ads in real-time"
    ;;
esac
