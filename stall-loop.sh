#!/usr/bin/env bash
# stall-loop.sh - Send varied prompts to Claude Code in tmux
#
# Human-like behavior:
#   - Random prompt from pool of 15+ tasks
#   - Random interval (MIN_INTERVAL-MAX_INTERVAL) instead of fixed
#   - Stops after MAX_CYCLES to simulate work sessions
#   - Logs prompt used for audit trail
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
COUNTER_FILE="/tmp/stall-loop-count"
PROMPT_FILE="/home/mylappy/Projects/opencode-proxy/prompts.txt"
CLAUDE_CMD="$(which claude 2>/dev/null || echo '/home/mylappy/.nvm/versions/node/v24.14.1/bin/claude')"

# Config with sensible defaults (override via env)
STALL=${STALL_SECONDS:-180}
MIN_INTERVAL=${MIN_INTERVAL:-180}
MAX_INTERVAL=${MAX_INTERVAL:-420}
MAX_CYCLES=${MAX_CYCLES:-0}  # 0 = unlimited

mkdir -p "$(dirname "$LOG")" "$(dirname "$COUNTER_FILE")"

pick_prompt() {
  if [ -f "$PROMPT_FILE" ]; then
    grep -v '^#' "$PROMPT_FILE" | grep -v '^[[:space:]]*$' | shuf -n1
  else
    echo "Count silently from 1 to 10000. For each number check if it is prime and compute its square root. Only output 'OK [N]' when done."
  fi
}

random_interval() {
  local min="${1:-$MIN_INTERVAL}"
  local max="${2:-$MAX_INTERVAL}"
  echo $(( RANDOM % (max - min + 1) + min ))
}

kill_old_loops() {
  [ -f "$PIDFILE" ] && kill "$(cat "$PIDFILE")" 2>/dev/null; rm -f "$PIDFILE"
  rm -f "$COUNTER_FILE"
  sleep 1
}

send_prompt() {
  local prompt
  prompt="$(pick_prompt)"
  tmux send-keys -l -t "$SESSION" "$prompt"
  sleep 0.5
  tmux send-keys -t "$SESSION" Enter
  echo "$prompt"
}

case "${1:-status}" in
  launch)
    kill_old_loops
    tmux kill-session -t "$SESSION" 2>/dev/null || true
    sleep 1
    tmux new-session -d -s "$SESSION" "$CLAUDE_CMD"
    tmux attach -t "$SESSION"
    ;;

  start)
    if ! tmux has-session -t "$SESSION" 2>/dev/null; then
      echo "ERROR: No tmux session. Run '$0 launch' first."
      exit 1
    fi
    kill_old_loops
    echo 0 > "$COUNTER_FILE"

    local prompt
    prompt="$(pick_prompt)"
    echo "[$(date '+%H:%M:%S')] Cycle 1/$MAX_CYCLES — sending prompt..." | tee -a "$LOG"
    echo "  Prompt: ${prompt:0:80}..." | tee -a "$LOG"
    send_prompt > /dev/null
    echo 1 > "$COUNTER_FILE"
    echo "[$(date '+%H:%M:%S')] First prompt sent." | tee -a "$LOG"

    (
      while true; do
        local interval
        interval="$(random_interval)"
        echo "[$(date '+%H:%M:%S')] Next prompt in ${interval}s." | tee -a "$LOG"
        sleep "$interval"

        local cycle
        cycle=$(cat "$COUNTER_FILE" 2>/dev/null || echo 0)
        cycle=$(( cycle + 1 ))

        if [ "$MAX_CYCLES" -gt 0 ] && [ "$cycle" -gt "$MAX_CYCLES" ]; then
          echo "[$(date '+%H:%M:%S')] Reached $MAX_CYCLES cycles. Stopping." | tee -a "$LOG"
          break
        fi

        local prompt
        prompt="$(pick_prompt)"
        echo "[$(date '+%H:%M:%S')] Cycle $cycle/$MAX_CYCLES — interval=${interval}s" | tee -a "$LOG"
        echo "  Prompt: ${prompt:0:80}..." | tee -a "$LOG"
        send_prompt > /dev/null
        echo "$cycle" > "$COUNTER_FILE"
        echo "[$(date '+%H:%M:%S')] Prompt sent." | tee -a "$LOG"
      done
      rm -f "$COUNTER_FILE" "$PIDFILE"
    ) &
    echo $! > "$PIDFILE"

    echo ""
    echo "Loop running. Watch: tmux attach -t $SESSION"
    echo "Stop: $0 stop"
    echo "Config: interval=${MIN_INTERVAL}-${MAX_INTERVAL}s max_cycles=${MAX_CYCLES}"
    ;;

  send)
    if ! tmux has-session -t "$SESSION" 2>/dev/null; then
      echo "ERROR: No tmux session."
      exit 1
    fi
    local prompt
    prompt="$(pick_prompt)"
    echo "[$(date '+%H:%M:%S')] Sending: ${prompt:0:80}..." | tee -a "$LOG"
    send_prompt > /dev/null
    ;;

  stop)
    kill_old_loops
    tmux kill-session -t "$SESSION" 2>/dev/null
    echo "Stopped."
    ;;

  status)
    tmux has-session -t "$SESSION" 2>/dev/null && echo "Session: RUNNING" || echo "Session: STOPPED"
    if [ -f "$PIDFILE" ]; then
      kill -0 "$(cat "$PIDFILE")" 2>/dev/null && echo "Loop: RUNNING" || echo "Loop: STOPPED"
    else
      echo "Loop: STOPPED"
    fi
    if [ -f "$COUNTER_FILE" ]; then
      echo "Cycles: $(cat "$COUNTER_FILE")/$MAX_CYCLES"
    fi
    echo "Config: interval=${MIN_INTERVAL}-${MAX_INTERVAL}s max_cycles=${MAX_CYCLES}"
    ;;

  attach)
    tmux attach -t "$SESSION"
    ;;

  *)
    echo "Usage: $0 {launch|start|send|attach|status|stop}"
    echo ""
    echo "Env overrides:"
    echo "  STALL_SECONDS=300     Base stall for proxy"
    echo "  MIN_INTERVAL=180      Min seconds between prompts"
    echo "  MAX_INTERVAL=420      Max seconds between prompts"
    echo "  MAX_CYCLES=20         Stop after N cycles (0=unlimited)"
    ;;
esac
