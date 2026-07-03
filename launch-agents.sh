#!/usr/bin/env bash
# launch-agents.sh - Run multiple Claude agents in parallel
#
# Each agent runs in its own tmux session (agent-1, agent-2, etc.)
# with its own auto-loop sending prompts every N seconds.
#
# Usage:
#   ./launch-agents.sh              # Launch dashboard (asks for count)
#   ./launch-agents.sh start        # Same as above
#   ./launch-agents.sh stop         # Kill all agents + loops
#   ./launch-agents.sh status       # Show status of all agents
#   ./launch-agents.sh attach <N>   # Attach to agent N

SESSION_PREFIX="agent"
PID_DIR="/tmp/agent-loop-pids"
LOG="$HOME/.claude-ad-loop.log"
STALL=${STALL_SECONDS:-300}
INTERVAL=$(( STALL + 30 ))
PROMPT="Count silently from 1 to 10000. For each number check if it is prime and compute its square root. Only output 'OK [N]' when done."

mkdir -p "$PID_DIR" "$(dirname "$LOG")"

send_prompt() {
  local session="$1"
  tmux send-keys -l -t "$session" "$PROMPT"
  sleep 0.5
  tmux send-keys -t "$session" Enter
}

start_one_agent() {
  local n="$1"
  local session="${SESSION_PREFIX}-${n}"
  local pidfile="${PID_DIR}/${session}.pid"

  # Kill old loop for this agent if any
  [ -f "$pidfile" ] && kill "$(cat "$pidfile")" 2>/dev/null; rm -f "$pidfile"

  # Kill old session if any
  tmux kill-session -t "$session" 2>/dev/null || true

  # Create new session with claude
  tmux new-session -d -s "$session" "claude"
  echo "Agent $n: tmux session '$session' created." | tee -a "$LOG"

  # Wait for Claude to be ready, then send first prompt
  sleep 5
  send_prompt "$session"
  echo "Agent $n: first prompt sent." | tee -a "$LOG"

  # Start background loop
  (
    while true; do
      sleep "$INTERVAL"
      send_prompt "$session"
      echo "[$(date '+%H:%M:%S')] Agent $n: prompt sent." | tee -a "$LOG"
    done
  ) &
  echo $! > "$pidfile"
  echo "Agent $n: loop started (PID $!)." | tee -a "$LOG"
}

stop_all() {
  for pidfile in "$PID_DIR"/*.pid; do
    [ -f "$pidfile" ] && kill "$(cat "$pidfile")" 2>/dev/null; rm -f "$pidfile"
  done
  for n in $(seq 1 100); do
    local session="${SESSION_PREFIX}-${n}"
    tmux has-session -t "$session" 2>/dev/null || break
    tmux kill-session -t "$session" 2>/dev/null
    echo "Agent $n: stopped." | tee -a "$LOG"
  done
  echo "All agents stopped." | tee -a "$LOG"
}

status_all() {
  local count=0
  for pidfile in "$PID_DIR"/*.pid; do
    [ -f "$pidfile" ] || continue
    local session_name=$(basename "$pidfile" .pid)
    local n="${session_name#${SESSION_PREFIX}-}"
    local running="no"
    tmux has-session -t "$session_name" 2>/dev/null && running="yes"
    local loop_running="no"
    kill -0 "$(cat "$pidfile")" 2>/dev/null && loop_running="yes"
    echo "Agent $n: session=$running loop=$loop_running (tmux: $session_name)"
    count=$((count + 1))
  done
  [ "$count" -eq 0 ] && echo "No agents running."
}

case "${1:-start}" in
  start)
    echo ""
    echo "=========================================="
    echo "  Multi-Agent Claude Launcher"
    echo "=========================================="
    read -r -p "  How many Claude agents to run? " COUNT
    echo ""

    # Validate
    [[ "$COUNT" =~ ^[0-9]+$ ]] || { echo "Enter a number."; exit 1; }
    [ "$COUNT" -gt 0 ] || { echo "Must be at least 1."; exit 1; }
    [ "$COUNT" -gt 20 ] && { echo "Max 20."; exit 1; }

    for i in $(seq 1 "$COUNT"); do
      start_one_agent "$i"
      sleep 2  # stagger launches
    done

    echo ""
    echo "=========================================="
    echo "  $COUNT agents running!"
    echo "=========================================="
    echo "  Attach:  ./launch-agents.sh attach <N>"
    echo "  Status:  ./launch-agents.sh status"
    echo "  Stop:    ./launch-agents.sh stop"
    echo "=========================================="
    echo ""

    # Show quick status
    status_all
    ;;

  stop)
    stop_all
    ;;

  status)
    status_all
    ;;

  attach)
    local n="${2:-1}"
    local session="${SESSION_PREFIX}-${n}"
    if tmux has-session -t "$session" 2>/dev/null; then
      tmux attach -t "$session"
    else
      echo "Agent $n not running."
    fi
    ;;

  *)
    echo "Usage: $0 [start|stop|status|attach <N>]"
    ;;
esac
