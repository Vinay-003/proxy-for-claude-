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
#   ./stall-loop.sh launch   # Create tmux session + open Claude
#   ./stall-loop.sh start    # Start auto-loop (sends prompt every ~5min)
#   ./stall-loop.sh send     # Manually send a prompt right now
#   ./stall-loop.sh attach   # Watch the ads in real-time
#   ./stall-loop.sh status   # Check if running
#   ./stall-loop.sh stop     # Kill everything

SESSION="stall-ads"
LOG="$HOME/.claude-ad-loop.log"
INTERVAL=${INTERVAL:-310}  # 5 min stall + ~10s response time

mkdir -p "$(dirname "$LOG")"

case "${1:-status}" in
  launch)
    tmux kill-session -t "$SESSION" 2>/dev/null || true
    sleep 1
    tmux new-session -s "$SESSION" "claude"
    ;;

  start)
    echo "Starting auto-loop (every ${INTERVAL}s)..." | tee -a "$LOG"
    echo "Make sure Claude is running in tmux session '$SESSION'." | tee -a "$LOG"
    echo "If not, run '$0 launch' first." | tee -a "$LOG"
    echo ""

    # Send first prompt immediately
    PROMPT="Count silently from 1 to 10000. For each number compute its square root to 10 decimal places. Only output 'OK [N]' when done. Do not show any work."
    tmux send-keys -t "$SESSION" "$PROMPT" Enter 2>/dev/null && \
      echo "[$(date '+%H:%M:%S')] First prompt sent." | tee -a "$LOG" || \
      { echo "ERROR: Cannot reach tmux session '$SESSION'. Run '$0 launch' first." | tee -a "$LOG"; exit 1; }

    # Background loop: send a new prompt every INTERVAL seconds
    (
      while true; do
        sleep "$INTERVAL"
        PROMPT="Count silently from 1 to 10000. For each number check if it is prime and compute its square root. Only output 'OK [N]' when done."
        tmux send-keys -t "$SESSION" "$PROMPT" Enter 2>/dev/null || true
        echo "[$(date '+%H:%M:%S')] Prompt sent via loop." | tee -a "$LOG"
      done
    ) &
    LOOP_PID=$!
    echo "$LOOP_PID" > /tmp/stall-loop-pid

    echo ""
    echo "============================================"
    echo "  ADS ARE RUNNING"
    echo "============================================"
    echo "  Watch:   tmux attach -t $SESSION"
    echo "  Detach:  Ctrl+B then D"
    echo "  Manual:  $0 send"
    echo "  Status:  $0 status"
    echo "  Stop:    $0 stop"
    echo "============================================"
    ;;

  send)
    PROMPT="Count silently from 1 to 10000. For each number check if it is prime and compute its square root. Only output 'OK [N]' when done."
    tmux send-keys -t "$SESSION" "$PROMPT" Enter
    echo "[$(date '+%H:%M:%S')] Prompt sent manually."
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
      echo "Claude session: RUNNING"
      echo "  Attach: tmux attach -t $SESSION"
    else
      echo "Claude session: STOPPED"
    fi
    if [ -f /tmp/stall-loop-pid ] && kill -0 "$(cat /tmp/stall-loop-pid)" 2>/dev/null; then
      echo "Auto-loop: RUNNING (sends prompt every ${INTERVAL}s)"
    else
      echo "Auto-loop: STOPPED"
    fi
    ;;

  attach)
    tmux attach -t "$SESSION"
    ;;

  *)
    echo "Usage: $0 {launch|start|send|attach|status|stop}"
    echo ""
    echo "  launch   Open Claude in a tmux session (you attach immediately)"
    echo "  start    Start auto-loop (send prompt now + every 5 min)"
    echo "  send     Manually send a prompt now"
    echo "  attach   Watch the ads (Ctrl+B then D to detach)"
    echo "  status   Check running state"
    echo "  stop     Kill everything"
    echo ""
    echo "Quick start:"
    echo "  STALL_SECONDS=300 ./toggle-model.sh start"
    echo "  ./toggle-model.sh free"
    echo "  ./stall-loop.sh launch    # opens Claude, press Enter to dismiss splash"
    echo "  # (in another terminal)"
    echo "  ./stall-loop.sh start"
    ;;
esac
