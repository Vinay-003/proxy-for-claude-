#!/usr/bin/env bash
# launch-agents.sh - Run multiple Claude agents
#
# Modes:
#   panes — one tmux session, tiled panes, all visible in one terminal
#   tabs  — one tmux session per agent, each in its own GNOME terminal tab
#
# Usage:
#   ./launch-agents.sh start           # Ask count + mode
#   ./launch-agents.sh panes           # Pane mode directly
#   ./launch-agents.sh tabs            # Tab mode directly
#   ./launch-agents.sh attach          # Attach to pane dashboard
#   ./launch-agents.sh status          # Show all agents
#   ./launch-agents.sh stop            # Kill everything

SESSION="agents"
PID_DIR="/tmp/agent-loop-pids"
LOG="$HOME/.claude-ad-loop.log"
STALL=${STALL_SECONDS:-300}
INTERVAL=$(( STALL + 30 ))
CLAUDE_CMD="$(which claude 2>/dev/null || echo '/home/mylappy/.nvm/versions/node/v24.14.1/bin/claude')"
PROMPT="Count silently from 1 to 10000. For each number check if it is prime and compute its square root. Only output 'OK [N]' when done."

mkdir -p "$PID_DIR" "$(dirname "$LOG")"

send_prompt() {
  local target="$1"
  tmux send-keys -l -t "$target" "$PROMPT"
  sleep 0.5
  tmux send-keys -t "$target" Enter
}

start_loop() {
  local n="$1"
  local target="$2"
  local pidfile="${PID_DIR}/agent-${n}.pid"

  sleep 5
  send_prompt "$target" &
  echo "Agent $n: first prompt sent." | tee -a "$LOG"

  (
    while true; do
      sleep "$INTERVAL"
      send_prompt "$target"
      echo "[$(date '+%H:%M:%S')] Agent $n: prompt sent." | tee -a "$LOG"
    done
  ) &
  echo $! > "$pidfile"
  echo "Agent $n: loop started (PID $!)." | tee -a "$LOG"
}

mode_panes() {
  local count="$1"

  for pidfile in "$PID_DIR"/*.pid; do
    [ -f "$pidfile" ] && kill "$(cat "$pidfile")" 2>/dev/null; rm -f "$pidfile"
  done
  tmux kill-session -t "$SESSION" 2>/dev/null || true
  sleep 1

  tmux new-session -d -s "$SESSION" "$CLAUDE_CMD"
  echo "Agent 1: launched." | tee -a "$LOG"

  for i in $(seq 2 "$count"); do
    tmux split-window -t "$SESSION" "$CLAUDE_CMD"
    echo "Agent $i: launched." | tee -a "$LOG"
  done

  tmux select-layout -t "$SESSION" tiled 2>/dev/null

  for i in $(seq 1 "$count"); do
    local pane_idx=$(( i - 1 ))
    start_loop "$i" "$SESSION:0.$pane_idx" &
    sleep 1
  done
  wait

  echo ""
  echo "=========================================="
  echo "  $count agents — PANE MODE"
  echo "=========================================="
  echo "  Attach:  tmux attach -t $SESSION"
  echo "  Zoom:    Ctrl+B then Z"
  echo "  Status:  ./launch-agents.sh status"
  echo "  Stop:    ./launch-agents.sh stop"
  echo "=========================================="
}

mode_tabs() {
  local count="$1"

  for pidfile in "$PID_DIR"/*.pid; do
    [ -f "$pidfile" ] && kill "$(cat "$pidfile")" 2>/dev/null; rm -f "$pidfile"
  done
  for i in $(seq 1 100); do
    tmux has-session -t "agent-${i}" 2>/dev/null || break
    tmux kill-session -t "agent-${i}" 2>/dev/null
  done
  sleep 1

  for i in $(seq 1 "$count"); do
    local ses="agent-${i}"
    tmux new-session -d -s "$ses" "$CLAUDE_CMD"
    echo "Agent $i: session '$ses' created." | tee -a "$LOG"
  done

  for i in $(seq 1 "$count"); do
    local ses="agent-${i}"
    start_loop "$i" "$ses" &
    sleep 1
  done
  wait

  for i in $(seq 1 "$count"); do
    local ses="agent-${i}"
    gnome-terminal --tab --title="Agent ${i}" -- bash -c "tmux attach -t '${ses}'; exec bash" &
    sleep 1
  done

  echo ""
  echo "=========================================="
  echo "  $count agents — TAB MODE"
  echo "=========================================="
  echo "  Each agent in its own GNOME terminal tab"
  echo "  Status:  ./launch-agents.sh status"
  echo "  Stop:    ./launch-agents.sh stop"
  echo "=========================================="
}

stop_all() {
  for pidfile in "$PID_DIR"/*.pid; do
    [ -f "$pidfile" ] && kill "$(cat "$pidfile")" 2>/dev/null; rm -f "$pidfile"
  done
  tmux kill-session -t "$SESSION" 2>/dev/null
  for i in $(seq 1 100); do
    tmux has-session -t "agent-${i}" 2>/dev/null || break
    tmux kill-session -t "agent-${i}" 2>/dev/null
  done
  echo "All agents stopped."
}

case "${1:-start}" in
  panes)
    echo ""
    read -r -p "  How many Claude agents? " COUNT
    [[ "$COUNT" =~ ^[0-9]+$ ]] && [ "$COUNT" -gt 0 ] && [ "$COUNT" -le 9 ] && mode_panes "$COUNT" || echo "Enter 1-9."
    ;;

  tabs)
    echo ""
    read -r -p "  How many Claude agents? " COUNT
    [[ "$COUNT" =~ ^[0-9]+$ ]] && [ "$COUNT" -gt 0 ] && [ "$COUNT" -le 9 ] && mode_tabs "$COUNT" || echo "Enter 1-9."
    ;;

  start)
    echo ""
    echo "=========================================="
    echo "  Multi-Agent Claude Launcher"
    echo "=========================================="
    echo "  Choose mode:"
    echo "    1) Panes — all visible in one terminal"
    echo "    2) Tabs  — one GNOME tab per agent"
    echo "=========================================="
    read -r -p "  Choice (1 or 2)? " MODE
    echo ""

    case "$MODE" in
      1) "$0" panes ;;
      2) "$0" tabs ;;
      *) echo "Invalid choice." && exit 1 ;;
    esac
    ;;

  attach)
    if tmux has-session -t "$SESSION" 2>/dev/null; then
      tmux attach -t "$SESSION"
    else
      echo "No pane dashboard running."
    fi
    ;;

  status)
    found=0
    if tmux has-session -t "$SESSION" 2>/dev/null; then
      echo "Pane dashboard: RUNNING"
      found=1
    fi
    for pidfile in "$PID_DIR"/*.pid; do
      [ -f "$pidfile" ] || continue
      n=$(basename "$pidfile" .pid | sed 's/agent-//')
      loop_running="no"
      kill -0 "$(cat "$pidfile")" 2>/dev/null && loop_running="yes"
      ses_running="no"
      tmux has-session -t "${SESSION}" 2>/dev/null && ses_running="yes"
      tmux has-session -t "agent-${n}" 2>/dev/null && ses_running="yes"
      echo "Agent $n: session=$ses_running loop=$loop_running"
      found=1
    done
    [ "$found" -eq 0 ] && echo "No agents running."
    ;;

  stop)
    stop_all
    ;;

  *)
    echo "Usage: $0 {start|panes|tabs|attach|status|stop}"
    ;;
esac
