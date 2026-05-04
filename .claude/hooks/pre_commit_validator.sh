#!/bin/bash
# =============================================================================
# Pre-Hook 3: Commit Message Validator
# Purpose:    Validate git commit messages follow conventional commit format.
#             Suggests a prefix if one is missing based on staged diff heuristics.
# Input:      JSON on stdin: {"tool_name":"Bash","tool_input":{"command":"..."},...}
# Exit codes: 0 = allow, 2 = block (invalid commit message)
# =============================================================================
# Resolve script directory and config paths
HOOK_DIR="$(cd "$(dirname "$0")" && pwd)"
PREFIX_FILE="$HOOK_DIR/config/commit_prefixes.txt"

INPUT="$(cat)"
COMMAND=$(printf '%s' "$INPUT" | grep -o '"command":"[^"]*"' | head -1 | sed 's/"command":"//;s/"//')

# Basic filter: only validate git commit commands with -m flag
if [[ ! "$COMMAND" =~ "git commit" ]] || [[ ! "$COMMAND" =~ "-m" ]]; then
    exit 0
fi

# Extract message content
COMMIT_MSG=$(echo "$COMMAND" | sed "s/.*-m ['\"]\(.*\)['\"].*/\1/")

# Load valid prefixes from config
if [ ! -f "$PREFIX_FILE" ]; then exit 0; fi
VALID_PREFIXES=$(paste -sd "|" "$PREFIX_FILE")
PREFIX_REGEX="^($VALID_PREFIXES):"

# Check 1: Prefix validation
if [[ ! "$COMMIT_MSG" =~ $PREFIX_REGEX ]]; then
    # Heuristic analysis
    STAGED_FILES=$(git diff --cached --name-only)
    STAGED_STATUS=$(git diff --cached --name-status)
    DIFF_STAT=$(git diff --cached --stat | tail -n 1)

    SUGGESTED="feat"
    if echo "$STAGED_FILES" | grep -iE "test|spec" >/dev/null; then
        SUGGESTED="test"
    elif echo "$STAGED_FILES" | grep -iE "README|\.md" >/dev/null; then
        SUGGESTED="docs"
    elif echo "$STAGED_STATUS" | grep "^A" >/dev/null; then
        SUGGESTED="feat"
    else
        INS=$(echo "$DIFF_STAT" | grep -o '[0-9]* insertion' | cut -d' ' -f1)
        DEL=$(echo "$DIFF_STAT" | grep -o '[0-9]* deletion' | cut -d' ' -f1)
        if [[ -n "$DEL" && -n "$INS" && "$DEL" -gt "$INS" ]]; then
            SUGGESTED="refactor"
        fi
    fi

    # Exact error message required by the test
    printf "Missing commit prefix. Based on your changes, try: '%s: %s'\n" "$SUGGESTED" "$COMMIT_MSG" >&2
    printf "Valid prefixes: %s\n" "$(echo "$VALID_PREFIXES" | sed 's/|/, /g')" >&2
    exit 2
fi

# Check 2: Length validation (10-72 chars)
MSG_LEN=${#COMMIT_MSG}
if (( MSG_LEN < 10 || MSG_LEN > 72 )); then
    printf "BLOCKED: Message length must be 10-72 characters.\n" >&2
    exit 2
fi

# Check 3: Punctuation (No trailing period)
if [[ "$COMMIT_MSG" =~ \.$ ]]; then
    printf "BLOCKED: Message must not end with a period.\n" >&2
    exit 2
fi

exit 0