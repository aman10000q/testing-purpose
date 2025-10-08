#!/bin/bash

send_slack() {
  local message="$1"
  local thread_ts="${2:-}"

  if echo "$message" | jq empty 2>/dev/null; then
    message=$(echo "$message" | jq '.')
  fi

  local payload
  payload=$(jq -n \
    --arg channel "$SLACK_CHANNEL_ID" \
    --arg text "$message" \
    --arg thread_ts "$thread_ts" \
    '{
      channel: $channel,
      text: $text
    } + (if $thread_ts != "" then {thread_ts: $thread_ts} else {} end)'
  )

  curl -s -X POST "https://slack.com/api/chat.postMessage" \
    -H "Authorization: Bearer $SLACK_TOKEN" \
    -H "Content-type: application/json" \
    -d "$payload" | jq '.'
}
