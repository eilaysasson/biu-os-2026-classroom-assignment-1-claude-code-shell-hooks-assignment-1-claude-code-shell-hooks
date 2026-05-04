#!/bin/bash
# =============================================================================
# Pre-Hook 2: Rate Limiter
# Purpose:    Track command count per session, block after exceeding limit.
# Input:      JSON on stdin: {"tool_name":"Bash","tool_input":{"command":"..."},"session_id":"..."}
# Exit codes: 0 = allow (possibly with warning), 2 = blocked (limit exceeded)
# State file: data/.command_count — format per line: session_id|total|type1:N,type2:N,...
# =============================================================================
#Resolve paths. Extract session_id and command. If session_id is absent, use "default".
# =============================================================================
HOOK_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_FILE="$HOOK_DIR/config/hooks.conf"
STATE_FILE="$HOOK_DIR/data/.command_count"
RESET_FILE="$HOOK_DIR/data/.reset_commands"

INPUT="$(cat)"
SESSION_ID=$(printf '%s' "$INPUT" | grep -o '"session_id":"[^"]*"' | head -1 | sed 's/"session_id":"//;s/"//')
if [ -z "$SESSION_ID" ]; then
    SESSION_ID="default"
fi

COMMAND=$(printf '%s' "$INPUT" | grep -o '"command":"[^"]*"' | head -1 | sed 's/"command":"//;s/"//')
#Reset mechanism: If .claude/hooks/data/.reset_commands exists
# =============================================================================
if [ -f "$RESET_FILE" ]; then
# delete this session's line from the state file
    sed -i "/^$SESSION_ID|/d" "$STATE_FILE"
    # remove the reset file, then proceed normally (count starts fresh at 1).
    rm -f "$RESET_FILE"
fi
# =============================================================================
#Read limits from .claude/hooks/config/hooks.conf:
# =============================================================================
#MAX_COMMANDS=50 — hard block threshold
MAX_COMMANDS=$(grep "MAX_COMMANDS" "$CONFIG_FILE" | cut -d'=' -f2)
#WARNING_THRESHOLD=40 — soft warning threshold
WARNING_THRESHOLD=$(grep "WARNING_THRESHOLD" "$CONFIG_FILE" | cut -d'=' -f2)
# =============================================================================
#Find the line for the current session_id (or start at 0 if not found).
# =============================================================================
OLD_LINE=$(grep "^$SESSION_ID|" "$STATE_FILE")
if [ -z "$OLD_LINE" ]; then
  Total_COUNT=0
  BREAKDOWN=""
  else
    Total_COUNT=$(echo "$OLD_LINE")
    BREAKDOWN=$(echo "$OLD_LINE" | cut -d'|' -f3)
fi
# =============================================================================
#Increment total count by 1.
# =============================================================================
Total_COUNT=$((Total_COUNT + 1))
# =============================================================================
#Extract the first word of the command (e.g., git from git commit -m ...) as the command type.
# =============================================================================
COMMAND_TYPE=$(echo "$COMMAND" | awk '{print $1}')

if [[ "$BREAKDOWN" == *"$COMMAND_TYPE:"* ]]; then
#Increment its per-type count.
    OLD_TYPE_COUNT=$(echo "$BREAKDOWN" | grep -o "$COMMAND_TYPE:[0-9]*" | cut -d':' -f2)
    NEW_TYPE_COUNT=$((OLD_TYPE_COUNT + 1))
    BREAKDOWN=$(echo "$BREAKDOWN" | sed "s/$COMMAND_TYPE:$OLD_TYPE_COUNT/$COMMAND_TYPE:$NEW_TYPE_COUNT/")
elif [ -z "$BREAKDOWN" ]; then
        BREAKDOWN="$COMMAND_TYPE:1"
    else
        BREAKDOWN="$BREAKDOWN,$COMMAND_TYPE:1"
fi
# =============================================================================
#Write the updated line back to the state file.
# =============================================================================
NEW_LINE="$SESSION_ID|$TOTAL_COUNT|$BREAKDOWN"
if [ -z "$OLD_LINE" ]; then
    echo "$NEW_LINE" >> "$STATE_FILE"
else
  #Replacing the old one for this session.
    sed -i "s/^$(echo "$OLD_LINE" | sed 's/[^^]/[&]/g; s/\^/\\^/g')\$/$NEW_LINE/" "$STATE_FILE"
fi
# =============================================================================
#Enforce limits:
# =============================================================================
if [ "$TOTAL_COUNT" -gt "$MAX_COMMANDS" ]; then
  #Total > MAX_COMMANDS → exit 2 with count and breakdown on stderr
  printf "BLOCKED: Rate limit exceeded (%d/%d). Breakdown: %s\n" "$TOTAL_COUNT" "$MAX_COMMANDS" "$BREAKDOWN" >&2
      exit 2
  #Total > WARNING_THRESHOLD → print warning to stderr, exit 0 (allow with warning)
  elif [ "$TOTAL_COUNT" -gt "$WARNING_THRESHOLD" ]; then
          printf "WARNING: Rate limit approaching (%d/%d).\n" "$TOTAL_COUNT" "$MAX_COMMANDS" >&2
          exit 0
fi
# =============================================================================
#Otherwise → exit 0 silently
exit 0

