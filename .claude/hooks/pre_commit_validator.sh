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

# Only validate commit commands with -m flag
if [[ ! "$COMMAND" =~ "git commit" ]] || [[ ! "$COMMAND" =~ "-m" ]]; then
    exit 0
fi

# Extract message content carefully
COMMIT_MSG=$(echo "$COMMAND" | sed -E "s/.*-m +['\"]([^'\"]+)['\"].*/\1/")

# Load valid prefixes from config file
if [ ! -f "$PREFIX_FILE" ]; then exit 0; fi
VALID_PREFIXES=$(paste -sd "|" "$PREFIX_FILE")
PREFIX_REGEX="^($VALID_PREFIXES):"

# Check 1: Prefix validation and Heuristic suggestion
if [[ ! "$COMMIT_MSG" =~ $PREFIX_REGEX ]]; then
    STAGED_FILES=$(git diff --cached --name-only)
    STAGED_STATUS=$(git diff --cached --name-status)
    DIFF_STAT=$(git diff --cached --stat | tail -n 1)

    # FIXED HEURISTIC PRIORITY:
    # 1. Tests 2. New Files (feat) 3. Documentation 4. Refactor
    if echo "$STAGED_FILES" | grep -iE "test|spec" >/dev/null; then
        SUGGESTED="test"
    elif echo "$STAGED_STATUS" | grep "^A" >/dev/null; then
        SUGGESTED="feat"
    elif echo "$STAGED_FILES" | grep -iE "README|\.md" >/dev/null; then
        SUGGESTED="docs"
    else
        # If more deletions than insertions, suggest refactor
        INS=$(echo "$DIFF_STAT" | grep -o '[0-9]* insertion' | cut -d' ' -f1)
        DEL=$(echo "$DIFF_STAT" | grep -o '[0-9]* deletion' | cut -d' ' -f1)
        if [[ -n "$DEL" && -n "$INS" && "$DEL" -gt "$INS" ]]; then
            SUGGESTED="refactor"
        else
            SUGGESTED="feat"
        fi
    fi

    printf "Missing commit prefix. Based on your changes, try: '%s: %s'\n" "$SUGGESTED" "$COMMIT_MSG" >&2
    printf "Valid prefixes: %s\n" "$(echo "$VALID_PREFIXES" | sed 's/|/, /g')" >&2
    exit 2
fi

# Check 2: Length validation
if (( ${#COMMIT_MSG} < 10 || ${#COMMIT_MSG} > 72 )); then
    printf "BLOCKED: Message length must be 10-72 characters.\n" >&2
    exit 2
fi

# Check 3: Punctuation check
if [[ "$COMMIT_MSG" =~ \.$ ]]; then
    printf "BLOCKED: Message must not end with a period.\n" >&2
    exit 2
fi

exit 0