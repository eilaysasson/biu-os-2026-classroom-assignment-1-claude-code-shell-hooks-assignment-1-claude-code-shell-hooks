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

# Read JSON input from stdin
INPUT="$(cat)"

# Extract the 'command' field from JSON (without jq)
COMMAND=$(printf '%s' "$INPUT" | grep -o '"command":"[^"]*"' | head -1 | sed 's/"command":"//;s/"//')

# Skip validation if it's not a git commit command or if it lacks the -m flag
if [[ ! "$COMMAND" =~ "git commit" ]] || [[ ! "$COMMAND" =~ "-m" ]]; then
    exit 0
fi

# Extract the commit message from the -m flag using sed capture groups
# Handles cases like -m "msg", -am 'msg', or -a -m "msg"
COMMIT_MSG=$(echo "$COMMAND" | sed "s/.*-m ['\"]\(.*\)['\"].*/\1/")

# Load valid prefixes from config and build a regex pattern
if [ ! -f "$PREFIX_FILE" ]; then
    exit 0 # If no config exists, allow the commit
fi

# Join lines with '|' to create a regex group (e.g., feat|fix|docs)
VALID_PREFIXES=$(paste -sd "|" "$PREFIX_FILE")
PREFIX_REGEX="^($VALID_PREFIXES):"

# =============================================================================
# Check 1: Conventional Prefix Validation & Heuristics
# =============================================================================
if [[ ! "$COMMIT_MSG" =~ $PREFIX_REGEX ]]; then
    # Start heuristic analysis of staged changes
    STAGED_FILES=$(git diff --cached --name-only)
    STAGED_STATUS=$(git diff --cached --name-status)
    DIFF_STAT=$(git diff --cached --stat | tail -n 1)

    SUGGESTED_PREFIX="feat" # Default suggestion

    # Heuristic Logic
    if echo "$STAGED_FILES" | grep -iE "test|spec" >/dev/null; then
        SUGGESTED_PREFIX="test"
    elif echo "$STAGED_FILES" | grep -iE "README|\.md" >/dev/null; then
        SUGGESTED_PREFIX="docs"
    elif echo "$STAGED_STATUS" | grep "^A" >/dev/null; then
        SUGGESTED_PREFIX="feat"
    else
        # If deletions outnumber insertions, suggest 'refactor'
        INSERTIONS=$(echo "$DIFF_STAT" | grep -o '[0-9]* insertion' | cut -d' ' -f1)
        DELETIONS=$(echo "$DIFF_STAT" | grep -o '[0-9]* deletion' | cut -d' ' -f1)

        if [[ -n "$DELETIONS" && -n "$INSERTIONS" && "$DELETIONS" -gt "$INSERTIONS" ]]; then
            SUGGESTED_PREFIX="refactor"
        fi
    fi

    # Print error and suggestion to stderr
    printf "BLOCKED: Missing or invalid prefix.\n" >&2
    printf "Based on your changes, try: '%s: %s'\n" "$SUGGESTED_PREFIX" "$COMMIT_MSG" >&2
    printf "Valid prefixes: %s\n" "$(echo "$VALID_PREFIXES" | sed 's/|/, /g')" >&2
    exit 2
fi

# =============================================================================
# Check 2: Length Validation (10-72 characters)
# =============================================================================
MESSAGE_LENGTH=${#COMMIT_MSG}
if (( MESSAGE_LENGTH < 10 || MESSAGE_LENGTH > 72 )); then
    printf "BLOCKED: Commit message length must be between 10 and 72 characters (current: %d).\n" "$MESSAGE_LENGTH" >&2
    exit 2
fi

# =============================================================================
# Check 3: Punctuation (No trailing period)
# =============================================================================
if [[ "$COMMIT_MSG" =~ \.$ ]]; then
    printf "BLOCKED: Commit message must not end with a period.\n" >&2
    exit 2
fi

# All checks passed
exit 0