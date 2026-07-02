#!/usr/bin/env bash
# stall-loop.sh - Keep Claude Code thinking = showing ads
#
# Usage:
#   ./stall-loop.sh launch   # Create tmux session + open Claude
#   ./stall-loop.sh start    # Start auto-loop (sends prompt when Claude is idle)
#   ./stall-loop.sh send     # Manually send a prompt right now
#   ./stall-loop.sh attach   # Watch the ads in real-time
#   ./stall-loop.sh status   # Check if running
#   ./stall-loop.sh stop     # Kill everything

SESSION="stall-ads"
LOG="$HOME/.claude-ad-loop.log"
PIDFILE="/tmp/stall-loop-pid"
PROMPT="Count silently from 1 to 10000. For each number check if it is prime and compute its square root. Only output 'OK [N]' when done."
STALL=${STALL_SECONDS:-300}
POLL_INTERVAL=5

mkdir -p "$(dirname "$LOG")"

kill_old_loops() {
  # Kill any old stall-loop background processes (zombies from previous runs)
  if [ -f "$PIDFILE" ]; then
    kill "$(cat "$PIDFILE")" 2>/dev/null
    rm -f "$PIDFILE"
  fi
  # Also kill any orphaned background loops from this script
  pkill -f "stall-loop.sh" 2>/dev/null || true
  sleep 1
}

is_claude_idle() {
  # Capture the tmux pane and check if Claude is showing the input prompt
  # When idle, the pane has a clean ">" prompt at the bottom
  # When busy, it shows "thinking", spinner, or ad text
  local pane_content
  pane_content=$(tmux capture-pane -p -t "$SESSION" 2>/dev/null) || return 1
  local last_lines
  last_lines=$(echo "$pane_content" | tail -5)

  # If any of the last 5 lines contain thinking indicators, Claude is busy
  if echo "$last_lines" | grep -qiE 'thinking|spinner|sauteed|·.*thinking'; then
    return 1  # busy
  fi

  # Check if there's a ">" prompt indicator (Claude is waiting for input)
  if echo "$last_lines" | grep -q '>'; then
    return 0  # idle
  fi

  # Default: assume busy if we can't tell
  return 1
}

send_prompt() {
  tmux send-keys -l -t "$SESSION" "$PROMPT"
  sleep 1
  tmux send-keys -t "$SESSION" Enter
}

wait_for_idle() {
  # After sending a prompt, wait for Claude to finish and return to idle
  # Max wait = stall time + 60s buffer for processing
  local max_wait=$(( STALL + 60 ))
  local elapsed=0

  echo "Waiting for Claude to finish (${max_wait}s max)..." | tee -a "$LOG"

  # First, wait for Claude to start thinking (prompt disappears)
  sleep 5

  # Then poll until Claude is idle again
  while [ "$elapsed" -lt "$max_wait" ]; do
    if is_claude_idle; then
      echo "Claude is idle after ${elapsed}s." | tee -a "$LOG"
      return 0
    fi
    sleep "$POLL_INTERVAL"
    elapsed=$(( elapsed + POLL_INTERVAL ))
  done

  echo "Timeout after ${max_wait}s, sending anyway." | tee -a "$LOG"
}

case "${1:-status}" in
  launch)
    kill_old_loops
    tmux kill-session -t "$SESSION" 2>/dev/null || true
    sleep 1
    tmux new-session -s "$SESSION" "claude"
    ;;

  start)
    if ! tmux has-session -t "$SESSION" 2>/dev/null; then
      echo "ERROR: tmux session '$SESSION' not found. Run '$0 launch' first." | tee -a "$LOG"
      exit 1
    fi

    kill_old_loops

    echo "Sending first prompt..." | tee -a "$LOG"
    send_prompt
    echo "[$(date '+%H:%M:%S')] First prompt sent." | tee -a "$LOG"

    # Background loop: wait for idle, then send next prompt
    (
      while true; do
        wait_for_idle
        send_prompt
        echo "[$(date '+%H:%M:%S')] Next prompt sent." | tee -a "$LOG"
      done
    ) &
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
    kill_old_loops
    tmux kill-session -t "$SESSION" 2>/dev/null || true
    echo "Stopped." | tee -a "$LOG"
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
