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
# Path resolution
HOOK_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_FILE="$HOOK_DIR/config/hooks.conf"
STATE_FILE="$HOOK_DIR/data/.command_count"
RESET_FILE="$HOOK_DIR/data/.reset_commands"

# Ensure data directory and state file exist
mkdir -p "$HOOK_DIR/data"
touch "$STATE_FILE"

# Parse JSON input
INPUT="$(cat)"
SESSION_ID=$(printf '%s' "$INPUT" | grep -o '"session_id":"[^"]*"' | head -1 | sed 's/"session_id":"//;s/"//')
[ -z "$SESSION_ID" ] && SESSION_ID="default"

COMMAND=$(printf '%s' "$INPUT" | grep -o '"command":"[^"]*"' | head -1 | sed 's/"command":"//;s/"//')
COMMAND_TYPE=$(echo "$COMMAND" | awk '{print $1}')

# Handle reset mechanism
if [ -f "$RESET_FILE" ]; then
    sed -i "/^$SESSION_ID|/d" "$STATE_FILE"
    rm -f "$RESET_FILE"
fi

# Load limits from config
MAX_COMMANDS=$(grep "MAX_COMMANDS" "$CONFIG_FILE" | cut -d'=' -f2)
WARNING_THRESHOLD=$(grep "WARNING_THRESHOLD" "$CONFIG_FILE" | cut -d'=' -f2)
[ -z "$MAX_COMMANDS" ] && MAX_COMMANDS=50
[ -z "$WARNING_THRESHOLD" ] && WARNING_THRESHOLD=40

# Find existing state for session
OLD_LINE=$(grep "^$SESSION_ID|" "$STATE_FILE")

if [ -z "$OLD_LINE" ]; then
    TOTAL_COUNT=0
    BREAKDOWN=""
else
    # Extract total count and breakdown string
    TOTAL_COUNT=$(echo "$OLD_LINE" | cut -d'|' -f2)
    BREAKDOWN=$(echo "$OLD_LINE" | cut -d'|' -f3)
fi

# Increment total count
TOTAL_COUNT=$((TOTAL_COUNT + 1))

# Update breakdown (e.g., git:3,ls:1)
if [[ "$BREAKDOWN" == *"$COMMAND_TYPE:"* ]]; then
    OLD_TYPE_COUNT=$(echo "$BREAKDOWN" | grep -o "$COMMAND_TYPE:[0-9]*" | cut -d':' -f2)
    NEW_TYPE_COUNT=$((OLD_TYPE_COUNT + 1))
    BREAKDOWN=$(echo "$BREAKDOWN" | sed "s/$COMMAND_TYPE:$OLD_TYPE_COUNT/$COMMAND_TYPE:$NEW_TYPE_COUNT/")
else
    if [ -z "$BREAKDOWN" ]; then
        BREAKDOWN="$COMMAND_TYPE:1"
    else
        BREAKDOWN="$BREAKDOWN,$COMMAND_TYPE:1"
    fi
fi

# Write updated state back to file
NEW_LINE="$SESSION_ID|$TOTAL_COUNT|$BREAKDOWN"
if [ -z "$OLD_LINE" ]; then
    echo "$NEW_LINE" >> "$STATE_FILE"
else
    sed -i "s/^$(echo "$OLD_LINE" | sed 's/[^^]/[&]/g; s/\^/\\^/g')\$/$NEW_LINE/" "$STATE_FILE"
fi

# Enforce limits based on the updated TOTAL_COUNT
if [ "$TOTAL_COUNT" -gt "$MAX_COMMANDS" ]; then
    printf "BLOCKED: Rate limit exceeded (%d/%d). Breakdown: %s\n" "$TOTAL_COUNT" "$MAX_COMMANDS" "$BREAKDOWN" >&2
    exit 2
elif [ "$TOTAL_COUNT" -gt "$WARNING_THRESHOLD" ]; then
    printf "WARNING: Rate limit approaching (%d/%d).\n" "$TOTAL_COUNT" "$MAX_COMMANDS" >&2
    exit 0
fi

exit 0

