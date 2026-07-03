#!/usr/bin/env bash
# launch-agents.sh - Run multiple Claude agents in tmux panes
#
# One tmux session "agents" with N panes — all visible at once.
#
# Usage:
#   ./launch-agents.sh start          # Ask count + launch
#   ./launch-agents.sh attach         # Attach to dashboard
#   ./launch-agents.sh status         # Show all agents
#   ./launch-agents.sh stop           # Kill everything

SESSION="agents"
PID_DIR="/tmp/agent-loop-pids"
LOG="$HOME/.claude-ad-loop.log"
STALL=${STALL_SECONDS:-300}
INTERVAL=$(( STALL + 30 ))
CLAUDE_CMD="$(which claude 2>/dev/null || echo '/home/mylappy/.nvm/versions/node/v24.14.1/bin/claude')"
PROMPT="Count silently from 1 to 10000. For each number check if it is prime and compute its square root. Only output 'OK [N]' when done."

mkdir -p "$PID_DIR" "$(dirname "$LOG")"

send_prompt() {
  local n="$1"
  local pane_idx=$(( n - 1 ))
  tmux send-keys -t "$SESSION:0.$pane_idx" "$PROMPT"
  sleep 0.5
  tmux send-keys -t "$SESSION:0.$pane_idx" Enter
}

start_all() {
  local count="$1"

  # Kill old everything
  for pidfile in "$PID_DIR"/*.pid; do
    [ -f "$pidfile" ] && kill "$(cat "$pidfile")" 2>/dev/null; rm -f "$pidfile"
  done
  tmux kill-session -t "$SESSION" 2>/dev/null || true
  sleep 1

  # First pane creates the session
  tmux new-session -d -s "$SESSION" "$CLAUDE_CMD"
  echo "Agent 1: launched." | tee -a "$LOG"

  # Split into panes for remaining agents
  for i in $(seq 2 "$count"); do
    tmux split-window -t "$SESSION" "$CLAUDE_CMD"
    echo "Agent $i: launched." | tee -a "$LOG"
  done

  # Even tiled layout
  tmux select-layout -t "$SESSION" tiled 2>/dev/null

  # Send first prompts + start loops
  for i in $(seq 1 "$count"); do
    local pidfile="${PID_DIR}/agent-${i}.pid"
    sleep 5
    send_prompt "$i" &
    echo "Agent $i: first prompt sent." | tee -a "$LOG"

    (
      while true; do
        sleep "$INTERVAL"
        send_prompt "$i"
        echo "[$(date '+%H:%M:%S')] Agent $i: prompt sent." | tee -a "$LOG"
      done
    ) &
    echo $! > "$pidfile"
    echo "Agent $i: loop started (PID $!)." | tee -a "$LOG"
  done

  echo ""
  echo "=========================================="
  echo "  $count agents in tmux session '$SESSION'"
  echo "=========================================="
  echo "  Attach:  tmux attach -t $SESSION"
  echo "  Zoom:    Ctrl+B then Z (on a pane)"
  echo "  Status:  ./launch-agents.sh status"
  echo "  Stop:    ./launch-agents.sh stop"
  echo "=========================================="
}

case "${1:-start}" in
  start)
    echo ""
    echo "=========================================="
    echo "  Multi-Agent Claude Launcher"
    echo "=========================================="
    read -r -p "  How many Claude agents to run? " COUNT
    echo ""
    [[ "$COUNT" =~ ^[0-9]+$ ]] || { echo "Enter a number."; exit 1; }
    [ "$COUNT" -gt 0 ] || { echo "Must be at least 1."; exit 1; }
    [ "$COUNT" -gt 9 ] && { echo "Max 9 (screen too small)."; exit 1; }
    start_all "$COUNT"
    ;;

  attach)
    if tmux has-session -t "$SESSION" 2>/dev/null; then
      tmux attach -t "$SESSION"
    else
      echo "No agents running. Run '$0 start' first."
    fi
    ;;

  status)
    if ! tmux has-session -t "$SESSION" 2>/dev/null; then
      echo "No agents running."
      exit 0
    fi
    for pidfile in "$PID_DIR"/*.pid; do
      [ -f "$pidfile" ] || continue
      local n=$(basename "$pidfile" .pid | sed 's/agent-//')
      local loop_running="no"
      kill -0 "$(cat "$pidfile")" 2>/dev/null && loop_running="yes"
      echo "Agent $n: pane exists, loop=$loop_running"
    done
    ;;

  stop)
    for pidfile in "$PID_DIR"/*.pid; do
      [ -f "$pidfile" ] && kill "$(cat "$pidfile")" 2>/dev/null; rm -f "$pidfile"
    done
    tmux kill-session -t "$SESSION" 2>/dev/null
    echo "All agents stopped."
    ;;

  *)
    echo "Usage: $0 {start|attach|status|stop}"
    ;;
esac
