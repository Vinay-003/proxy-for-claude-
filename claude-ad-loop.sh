#!/usr/bin/env bash
# claude-ad-loop.sh - Keep Claude Code busy earning ads
# Opens Claude in a tmux session and keeps sending prompts
# that trigger long internal reasoning (spinner = ads).

set -e
SESSION="claude-ads"
PROMPTS_FILE="$HOME/.claude-ad-prompts"
DEFAULT_PROMPT='Count silently from 1 to 5000. For each number compute its square root to 10 decimal places and check if it is prime. Do all work internally. Only reply with "OK [N]" where N is the count when finished. Do not show any intermediate steps.'

mkdir -p "$HOME/.claude-ad-prompts"

case "${1:-}" in
  install)
    echo "Installing dependencies..."
    if ! command -v tmux &>/dev/null; then
      echo "Installing tmux..."
      sudo apt-get install -y tmux
    fi
    echo "Creating default prompt file..."
    echo "$DEFAULT_PROMPT" > "$PROMPTS_FILE"
    echo "Done. Run '$0 start' to begin."
    ;;

  start|resume)
    # Kill any existing session with same name
    tmux kill-session -t "$SESSION" 2>/dev/null || true
    sleep 1
    echo "Starting Claude Code in tmux session '$SESSION'..."
    tmux new-session -d -s "$SESSION" "claude"
    echo "Waiting for Claude to start..."
    sleep 5
    echo "Sending first prompt..."
    PROMPT=$(cat "$PROMPTS_FILE" 2>/dev/null || echo "$DEFAULT_PROMPT")
    tmux send-keys -t "$SESSION" "$PROMPT" Enter
    echo "Claude is running. Attach: tmux attach -t $SESSION"
    echo "Detach: Ctrl+B, D"
    ;;

  stop)
    tmux kill-session -t "$SESSION" 2>/dev/null || true
    echo "Stopped."
    ;;

  status)
    if tmux has-session -t "$SESSION" 2>/dev/null; then
      echo "Claude-ads session: RUNNING"
      echo "Attach: tmux attach -t $SESSION"
    else
      echo "Claude-ads session: STOPPED"
    fi
    ;;

  next)
    # Manually send the next prompt (for when you see Claude has finished)
    PROMPT=$(cat "$PROMPTS_FILE" 2>/dev/null || echo "$DEFAULT_PROMPT")
    tmux send-keys -t "$SESSION" "$PROMPT" Enter
    echo "Sent next prompt."
    ;;

  set-prompt)
    # Set a custom prompt
    shift
    echo "$*" > "$PROMPTS_FILE"
    echo "Prompt saved."
    ;;

  loop)
    # Automatic loop mode - keeps sending prompts every N seconds
    INTERVAL=${2:-90}
    echo "Starting auto-loop every ${INTERVAL}s. Ctrl+C to stop."
    echo "Run '$0 start' in another terminal first."
    while true; do
      PROMPT=$(cat "$PROMPTS_FILE" 2>/dev/null || echo "$DEFAULT_PROMPT")
      tmux send-keys -t "$SESSION" "$PROMPT" Enter
      echo "[$(date '+%H:%M:%S')] Sent prompt. Next in ${INTERVAL}s..."
      sleep "$INTERVAL"
    done
    ;;

  headless)
    # Bypass Claude Code entirely - hit the proxy directly
    # NOTE: This does NOT show ads (no Claude UI running)
    # Use this if you just want to use API with zero output
    echo "Running headless (no ads - no Claude UI)..."
    INTERVAL=${2:-30}
    PROMPT=$(cat "$PROMPTS_FILE" 2>/dev/null || echo "$DEFAULT_PROMPT")
    while true; do
      echo "[$(date '+%H:%M:%S')] Sending request..."
      curl -s -X POST http://127.0.0.1:5454/v1/messages \
        -H "Content-Type: application/json" \
        -H "x-api-key: dummy" \
        -H "anthropic-version: 2023-06-01" \
        -d '{
          "model": "claude-haiku-4-5-20251001",
          "max_tokens": 256,
          "stream": true,
          "messages": [{"role": "user", "content": '"$(echo "$PROMPT" | jq -Rs .)"'}]
        }' > /dev/null 2>&1
      echo "[$(date '+%H:%M:%S')] Done. Next in ${INTERVAL}s..."
      sleep "$INTERVAL"
    done
    ;;

  *)
    echo "Usage: $0 {install|start|stop|status|next|loop|set-prompt|headless}"
    echo ""
    echo "Commands:"
    echo "  install       Install tmux and create default prompt"
    echo "  start         Launch Claude Code in tmux and send first prompt"
    echo "  stop          Kill the tmux session"
    echo "  status        Check if session is running"
    echo "  next          Send another prompt (after Claude finishes)"
    echo "  loop [sec]    Auto-send prompt every N seconds (default 90)"
    echo "  set-prompt    Save a custom prompt for the loop"
    echo "  headless      Direct API calls (no Claude UI, no ads)"
    echo ""
    echo "Quick start:"
    echo "  $0 install"
    echo "  $0 start"
    echo "  tmux attach -t claude-ads    # watch the ads roll"
    echo "  # Press Ctrl+B then D to detach and let it run"
    ;;
esac
