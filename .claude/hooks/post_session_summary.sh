#!/bin/bash
# =============================================================================
# Post-Hook 6: Session Summary
# Purpose:    Generate a formatted summary from session.log when Claude stops.
# Input:      JSON on stdin: {"session_id":"...","cwd":"...","stop_hook_active":false}
# Exit codes: 0 always
# IMPORTANT:  Checks stop_hook_active first to prevent infinite loops.
# =============================================================================
# 1. Infinite-loop guard (Critical!)
INPUT=$(cat)
STOP_HOOK_ACTIVE=$(echo "$INPUT" | grep -o '"stop_hook_active":[^,}]*' | cut -d':' -f2 | tr -d ' "')

if [ "$STOP_HOOK_ACTIVE" = "true" ]; then
    exit 0
fi

# 2. Extract Session ID and define paths
SESSION_ID=$(echo "$INPUT" | grep -o '"session_id":"[^"]*"' | head -1 | sed 's/"session_id":"//;s/"//')
[ -z "$SESSION_ID" ] && SESSION_ID="default"

HOOK_DIR="$(cd "$(dirname "$0")" && pwd)"
LOG_FILE="$HOOK_DIR/data/session_${SESSION_ID}.log"

# 3. Validation
if [ ! -f "$LOG_FILE" ] || [ ! -s "$LOG_FILE" ]; then
    printf '{"systemMessage": "No session activity recorded."}\n'
    exit 0
fi

# 4. Gather Statistics
TOTAL_ACTIONS=$(wc -l < "$LOG_FILE")
BACKUPS=$(grep -c "BACKUP" "$LOG_FILE")
SYNTAX_OK=$(grep -c "SYNTAX_OK" "$LOG_FILE")
SYNTAX_ERR=$(grep -c "SYNTAX_ERROR" "$LOG_FILE")

# Top 3 Most-Edited Files
# FIX: Use $4 to get the filename, not $3 which is the word "BACKUP"
TOP_FILES=$(grep "BACKUP" "$LOG_FILE" | awk '{print $4}' | xargs -n1 basename | sort | uniq -c | sort -nr | head -n 3 | awk '{printf "%s (%s), ", $2, $1}' | sed 's/, $//')

# 5. Generate Formatted Report
# Exact labels required by the automated test suite
REPORT_MSG="SESSION SUMMARY REPORT: $SESSION_ID\n"
REPORT_MSG="${REPORT_MSG}Total actions: $TOTAL_ACTIONS\n"
REPORT_MSG="${REPORT_MSG}Backups made: $BACKUPS\n"
REPORT_MSG="${REPORT_MSG}Syntax checks: $SYNTAX_OK\n"
REPORT_MSG="${REPORT_MSG}Syntax errors: $SYNTAX_ERR\n"
REPORT_MSG="${REPORT_MSG}Most edited files: $TOP_FILES"

# 6. Output as Claude Code systemMessage
printf '{"systemMessage": "%b"}\n' "$REPORT_MSG"

exit 0