#!/bin/bash

send_slack() {
  local message="$1"
  local thread_ts="${2:-}"  # optional second argument

  # Build base JSON payload
  local payload
  if [[ -z "$thread_ts" ]]; then
    payload=$(jq -n --arg channel "$CHANNEL_ID" --arg text "$message" '{channel: $channel, text: $text}')
  else
    payload=$(jq -n --arg channel "$CHANNEL_ID" --arg text "$message" --arg thread "$thread_ts" '{channel: $channel, text: $text, thread_ts: $thread}')
  fi

  # Send message
  local response
  response=$(curl -s -X POST "https://slack.com/api/chat.postMessage" \
    -H "Content-type: application/json; charset=utf-8" \
    -H "Authorization: Bearer $SLACK_TOKEN" \
    -d "$payload")

  # Debugging
  echo "Slack response: $response" >&2

  # Return ts if it's a top-level message (thread starter)
  if [[ -z "$thread_ts" ]]; then
    echo "$response" | jq -r '.ts // empty'
  fi
}
