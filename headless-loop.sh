#!/usr/bin/env bash
# headless-loop.sh - Hit the proxy API directly in a loop
# No Claude Code UI needed. Keeps the free model busy thinking.
set -euo pipefail

PROXY_URL="http://127.0.0.1:5454"
PROMPT=${PROMPT:-'Count silently from 1 to 3000. For each number compute its square root to 10 decimal places and check if it is prime. Do all work internally. Only reply with "OK [N]" where N is the count. Never show intermediate steps.'}
MODEL=${MODEL:-'claude-haiku-4-5-20251001'}
INTERVAL=${INTERVAL:-45}
COUNT=0
LOG="$HOME/.claude-ad-loop.log"

cleanup() {
  echo "" | tee -a "$LOG"
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] Stopped. Sent $COUNT requests total." | tee -a "$LOG"
  exit 0
}
trap cleanup SIGINT SIGTERM

echo "===== Claude Headless Ad Loop =====" | tee -a "$LOG"
echo "Proxy: $PROXY_URL" | tee -a "$LOG"
echo "Model: $MODEL" | tee -a "$LOG"
echo "Interval: ${INTERVAL}s" | tee -a "$LOG"
echo "Log: $LOG" | tee -a "$LOG"
echo "Press Ctrl+C to stop." | tee -a "$LOG"
echo "" | tee -a "$LOG"

if ! curl -sf "$PROXY_URL/v1/models" > /dev/null 2>&1; then
  echo "ERROR: Proxy not running at $PROXY_URL" | tee -a "$LOG"
  echo "Start it first: toggle-model.sh start" | tee -a "$LOG"
  exit 1
fi

while true; do
  COUNT=$((COUNT + 1))
  TSTART=$(date +%s)
  echo "[$(date '+%H:%M:%S')] Request #$COUNT - sending..." | tee -a "$LOG"

  set +e
  curl -s -X POST "$PROXY_URL/v1/messages" \
    -H "Content-Type: application/json" \
    -H "x-api-key: dummy" \
    -H "anthropic-version: 2023-06-01" \
    -d '{
      "model": "'"$MODEL"'",
      "max_tokens": 256,
      "stream": true,
      "messages": [{"role": "user", "content": '"$(printf '%s' "$PROMPT" | jq -Rs .)"'}]
    }' 2>/dev/null | (
      # Stream mode - read SSE events, count thinking blocks
      THINKING=0
      TEXT=""
      while IFS= read -r line; do
        case "$line" in
          data:*)
            data="${line#data: }"
            if echo "$data" | grep -q '"type":"content_block_delta".*"type":"thinking_delta"'; then
              THINKING=$((THINKING + $(echo "$data" | python3 -c "import json,sys; d=json.load(sys.stdin); print(len(d.get('delta',{}).get('thinking','')))" 2>/dev/null || echo 0)))
            elif echo "$data" | grep -q '"type":"content_block_delta".*"type":"text_delta"'; then
              chunk=$(echo "$data" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('delta',{}).get('text',''))" 2>/dev/null || echo "")
              TEXT+="$chunk"
            elif echo "$data" | grep -q '"type":"message_stop"'; then
              echo "" >> /dev/null
            fi
            ;;
        esac
      done
      echo "THINKING=$THINKING" > /tmp/.claude-ad-last-thinking
      echo "TEXT=$TEXT" > /tmp/.claude-ad-last-text
    )
  EXIT_CODE=$?
  set -e

  TDUR=$(($(date +%s) - TSTART))

  THINKING=$(cat /tmp/.claude-ad-last-thinking 2>/dev/null || echo "0")
  THINKING="${THINKING#THINKING=}"
  RESP_TEXT=$(cat /tmp/.claude-ad-last-text 2>/dev/null || echo "")
  RESP_TEXT="${RESP_TEXT#TEXT=}"

  if [ $EXIT_CODE -ne 0 ]; then
    echo "[$(date '+%H:%M:%S')] Request #$COUNT FAILED (exit=$EXIT_CODE) in ${TDUR}s" | tee -a "$LOG"
  else
    echo "[$(date '+%H:%M:%S')] Request #$COUNT done in ${TDUR}s | thinking chars: ${THINKING} | reply: ${RESP_TEXT:0:80}" | tee -a "$LOG"
  fi

  if [ "$INTERVAL" -gt 0 ]; then
    NEXT=$((TSTART + INTERVAL - $(date +%s)))
    [ "$NEXT" -lt 1 ] && NEXT=1
    echo "  Next request in ${NEXT}s..." | tee -a "$LOG"
    sleep "$NEXT"
  fi
done
