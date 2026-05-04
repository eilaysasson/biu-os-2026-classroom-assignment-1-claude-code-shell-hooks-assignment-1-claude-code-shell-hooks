#!/bin/bash
# =============================================================================
# Post-Hook 5: Syntax Checker
# Purpose:    Run appropriate syntax checker based on file extension after edit.
# Input:      JSON on stdin: {"tool_name":"Edit","tool_input":{"file_path":"..."},...}
# Exit codes: 0 = syntax OK (or no checker), 1 = syntax error (warn, don't block)
# Supported:  .sh/.bash (bash -n), .py (python3 -m py_compile), .c/.h (gcc -fsyntax-only)
# =============================================================================
# Path resolution
HOOK_DIR="$(cd "$(dirname "$0")" && pwd)"
LOG_DIR="$HOOK_DIR/data"

# Read JSON input from stdin
INPUT="$(cat)"

# Extract file_path and session_id
FILE_PATH=$(printf '%s' "$INPUT" | grep -o '"file_path":"[^"]*"' | head -1 | sed 's/"file_path":"//;s/"//')
SESSION_ID=$(printf '%s' "$INPUT" | grep -o '"session_id":"[^"]*"' | head -1 | sed 's/"session_id":"//;s/"//')
[ -z "$SESSION_ID" ] && SESSION_ID="default"

# Validate file existence
if [ -z "$FILE_PATH" ] || [ ! -f "$FILE_PATH" ]; then
    exit 0
fi

# Extract file extension
EXTENSION="${FILE_PATH##*.}"
SESSION_LOG="$LOG_DIR/session_$SESSION_ID.log"
TIMESTAMP=$(date "+%Y-%m-%d %H:%M:%S")

# Dispatch syntax checker based on extension
case "$EXTENSION" in
    sh|bash)
        CHECK_CMD="bash -n \"$FILE_PATH\""
        ;;
    py)
        # Using python3 -m py_compile for silent syntax checking
        CHECK_CMD="python3 -m py_compile \"$FILE_PATH\""
        ;;
    c|h)
        # gcc -fsyntax-only checks code without producing an executable
        CHECK_CMD="gcc -fsyntax-only \"$FILE_PATH\""
        ;;
    *)
        printf "No syntax checker for .%s\n" "$EXTENSION" >&2
        exit 0
        ;;
esac

# Execute checker and capture output/exit code
# 2>&1 redirects stderr to stdout so we capture all error messages
ERROR_OUTPUT=$(eval "$CHECK_CMD" 2>&1)
EXIT_CODE=$?

if [ $EXIT_CODE -ne 0 ]; then
    # Handle failure
    printf "SYNTAX ERROR in %s:\n%s\n" "$FILE_PATH" "$ERROR_OUTPUT" >&2
    echo "[$TIMESTAMP] SYNTAX_ERROR $FILE_PATH ($EXTENSION)" >> "$SESSION_LOG"
    exit 1
else
    # Handle success
    printf "Syntax OK: %s\n" "$FILE_PATH"
    echo "[$TIMESTAMP] SYNTAX_OK $FILE_PATH ($EXTENSION)" >> "$SESSION_LOG"
    exit 0
fi