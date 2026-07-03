#!/usr/bin/env bash
# launch-agents.sh - Run multiple Claude agents with human-like variation
#
# Each agent gets:
#   - Different prompt pool (slightly shuffled)
#   - Different interval range (natural variation)
#   - Different max cycles (agents stop at different times)
#   - Staggered start delays
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
CLAUDE_CMD="$(which claude 2>/dev/null || echo '/home/mylappy/.nvm/versions/node/v24.14.1/bin/claude')"
PROMPT_FILE="/home/mylappy/Projects/opencode-proxy/prompts.txt"

mkdir -p "$PID_DIR" "$(dirname "$LOG")"

send_prompt() {
  local target="$1"
  local file="$2"
  local prompt
  prompt="$(grep -v '^#' "$file" | grep -v '^[[:space:]]*$' | shuf -n1)"
  tmux send-keys -l -t "$target" "$prompt"
  sleep 0.5
  tmux send-keys -t "$target" Enter
}

# Generate per-agent config with variation
gen_config() {
  local n="$1"
  local min_interval max_interval max_cycles start_delay
  # Spread intervals: agent 1 fastest, agent 5 slowest
  min_interval=$(( 120 + n * 30 + RANDOM % 60 ))
  max_interval=$(( min_interval + 120 + RANDOM % 120 ))
  max_cycles=$(( 8 + n * 2 + RANDOM % 5 ))  # agents run different lengths
  start_delay=$(( n * 8 + RANDOM % 15 ))     # staggered start
  echo "$min_interval $max_interval $max_cycles $start_delay"
}

start_loop() {
  local n="$1"
  local target="$2"
  local prompt_file="${PID_DIR}/prompts-agent-${n}.txt"
  local pidfile="${PID_DIR}/agent-${n}.pid"
  local counter="${PID_DIR}/count-${n}"
  local conf_file="${PID_DIR}/conf-${n}"
  local min_interval max_interval max_cycles start_delay

  read -r min_interval max_interval max_cycles start_delay < "$conf_file"

  sleep "$start_delay"

  local prompt
  prompt="$(grep -v '^#' "$prompt_file" | grep -v '^[[:space:]]*$' | shuf -n1)"
  tmux send-keys -l -t "$target" "$prompt"
  sleep 0.5
  tmux send-keys -t "$target" Enter
  echo "1" > "$counter"
  echo "Agent $n: first prompt sent. (delay=${start_delay}s)" | tee -a "$LOG"

  (
    while true; do
      local interval
      interval=$(( min_interval + RANDOM % (max_interval - min_interval + 1) ))
      sleep "$interval"

      local cycle
      cycle=$(cat "$counter" 2>/dev/null || echo 0)
      cycle=$(( cycle + 1 ))

      if [ "$cycle" -gt "$max_cycles" ]; then
        echo "Agent $n: reached $max_cycles cycles. Stopping." | tee -a "$LOG"
        break
      fi

      local prompt
      prompt="$(grep -v '^#' "$prompt_file" | grep -v '^[[:space:]]*$' | shuf -n1)"
      tmux send-keys -l -t "$target" "$prompt"
      sleep 0.5
      tmux send-keys -t "$target" Enter
      echo "$cycle" > "$counter"
      echo "[$(date '+%H:%M:%S')] Agent $n: cycle $cycle/$max_cycles (interval=${interval}s)" | tee -a "$LOG"
    done
    rm -f "$counter" "$pidfile"
  ) &
  echo $! > "$pidfile"
  echo "Agent $n: loop started (PID $!, config=${min_interval}-${max_interval}s × ${max_cycles}cyc)." | tee -a "$LOG"
}

mode_panes() {
  local count="$1"

  for pidfile in "$PID_DIR"/*.pid; do
    [ -f "$pidfile" ] && kill "$(cat "$pidfile")" 2>/dev/null; rm -f "$pidfile"
  done
  tmux kill-session -t "$SESSION" 2>/dev/null || true
  sleep 1

  # Create per-agent prompt files (shuffled uniquely per agent)
  for i in $(seq 1 "$count"); do
    grep -v '^#' "$PROMPT_FILE" | grep -v '^[[:space:]]*$' | shuf > "${PID_DIR}/prompts-agent-${i}.txt"
    gen_config "$i" > "${PID_DIR}/conf-${i}"
  done

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
    sleep 2
  done
  wait

  echo ""
  echo "=========================================="
  echo "  $count agents — PANE MODE"
  echo "  Each agent: varied interval, prompt, cycles"
  echo "=========================================="
  echo "  Attaching in 3s..."
  echo "  Detach:  Ctrl+B then D"
  echo "  Zoom:    Ctrl+B then Z"
  echo "  Status:  ./launch-agents.sh status"
  echo "  Stop:    ./launch-agents.sh stop"
  echo "=========================================="
  sleep 3
  tmux attach -t "$SESSION"
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

  # Create per-agent prompt files (shuffled uniquely per agent)
  for i in $(seq 1 "$count"); do
    grep -v '^#' "$PROMPT_FILE" | grep -v '^[[:space:]]*$' | shuf > "${PID_DIR}/prompts-agent-${i}.txt"
    gen_config "$i" > "${PID_DIR}/conf-${i}"
  done

  for i in $(seq 1 "$count"); do
    local ses="agent-${i}"
    tmux new-session -d -s "$ses" "$CLAUDE_CMD"
    echo "Agent $i: session '$ses' created." | tee -a "$LOG"
  done

  for i in $(seq 1 "$count"); do
    local ses="agent-${i}"
    start_loop "$i" "$ses" &
    sleep 2
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
  echo "  Each agent: varied interval, prompt, cycles"
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
  rm -rf "$PID_DIR"
  echo "All agents stopped."
}

case "${1:-start}" in
  panes)
    echo ""
    read -r -p "  How many Claude agents (1-5)? " COUNT
    [[ "$COUNT" =~ ^[0-9]+$ ]] && [ "$COUNT" -gt 0 ] && [ "$COUNT" -le 5 ] && mode_panes "$COUNT" || echo "Enter 1-5."
    ;;

  tabs)
    echo ""
    read -r -p "  How many Claude agents (1-5)? " COUNT
    [[ "$COUNT" =~ ^[0-9]+$ ]] && [ "$COUNT" -gt 0 ] && [ "$COUNT" -le 5 ] && mode_tabs "$COUNT" || echo "Enter 1-5."
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
    echo ""
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
    for conf in "$PID_DIR"/conf-*; do
      [ -f "$conf" ] || continue
      n=$(basename "$conf" | sed 's/conf-//')
      pidfile="${PID_DIR}/agent-${n}.pid"
      counter="${PID_DIR}/count-${n}"
      loop_running="no"
      [ -f "$pidfile" ] && kill -0 "$(cat "$pidfile")" 2>/dev/null && loop_running="yes"
      ses_running="no"
      tmux has-session -t "$SESSION" 2>/dev/null && ses_running="yes"
      tmux has-session -t "agent-${n}" 2>/dev/null && ses_running="yes"

      cycles="?"
      [ -f "$counter" ] && cycles=$(cat "$counter")

      desc=""
      if [ -f "$conf" ]; then
        read -r mi ma mc sd < "$conf"
        desc="interval=${mi}-${ma}s cycles=${cycles}/${mc}"
      fi

      echo "Agent $n: session=$ses_running loop=$loop_running $desc"
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
