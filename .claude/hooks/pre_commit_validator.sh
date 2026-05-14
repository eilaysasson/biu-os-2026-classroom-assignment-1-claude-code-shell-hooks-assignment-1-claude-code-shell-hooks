#!/bin/bash
# =============================================================================
# Pre-Hook 3: Commit Message Validator
# Purpose:    Validate git commit messages follow conventional commit format.
#             Suggests a prefix if one is missing based on staged diff heuristics.
# Input:      JSON on stdin: {"tool_name":"Bash","tool_input":{"command":"..."},...}
# Exit codes: 0 = allow, 2 = block (invalid commit message)
# =============================================================================
HOOK_DIR="$(cd "$(dirname "$0")" && pwd)"
PREFIX_FILE="$HOOK_DIR/config/commit_prefixes.txt"

INPUT="$(cat)"
COMMAND=$(printf '%s' "$INPUT" | grep -o '"command":"[^"]*"' | head -1 | sed 's/"command":"//;s/"//')

# Step 1: Inspect only git commit commands that use the -m flag
if [[ ! "$COMMAND" =~ "git commit" ]] || [[ ! "$COMMAND" =~ "-m" ]]; then
    exit 0
fi

# Step 2: Extract commit message content using sed regex capture
COMMIT_MSG=$(echo "$COMMAND" | sed -E "s/.*-m +['\"]([^'\"]+)['\"].*/\1/")

# Step 3: Validate prefix against allowed prefixes defined in config
if [ ! -f "$PREFIX_FILE" ]; then exit 0; fi
VALID_PREFIXES=$(paste -sd "|" "$PREFIX_FILE")
if [[ ! "$COMMIT_MSG" =~ ^($VALID_PREFIXES): ]]; then

    # Step 4: Heuristics - analyze staged changes to suggest a valid prefix
    STAGED_FILES=$(git diff --cached --name-only)
    STAGED_STATUS=$(git diff --cached --name-status)
    DIFF_STAT=$(git diff --cached --stat | tail -n 1)

    if echo "$STAGED_FILES" | grep -iE "test|spec" >/dev/null; then
        SUGGESTED="test"
    elif echo "$STAGED_STATUS" | grep "^A" >/dev/null; then
        SUGGESTED="feat" # Staged new files suggest a feature
    elif echo "$STAGED_FILES" | grep -iE "README|\.md" >/dev/null; then
        SUGGESTED="docs"
    else
        # Suggest refactor if deletions outweigh insertions
        INS=$(echo "$DIFF_STAT" | grep -o '[0-9]* insertion' | cut -d' ' -f1)
        DEL=$(echo "$DIFF_STAT" | grep -o '[0-9]* deletion' | cut -d' ' -f1)
        [[ -n "$DEL" && -n "$INS" && "$DEL" -gt "$INS" ]] && SUGGESTED="refactor" || SUGGESTED="feat"
    fi

    # Step 5: Block execution and provide a correction suggestion (including valid prefixes string)
    printf "Missing commit prefix. Based on your changes, try: '%s: %s'\n" "$SUGGESTED" "$COMMIT_MSG" >&2
    printf "Valid prefixes: %s\n" "$(echo "$VALID_PREFIXES" | sed 's/|/, /g')" >&2
    exit 2
fi

# Step 6: Enforce length constraints (10-72 chars) and period formatting
if (( ${#COMMIT_MSG} < 10 || ${#COMMIT_MSG} > 72 )); then
    printf "BLOCKED: Message length must be 10-72 characters.\n" >&2
    exit 2
fi

if [[ "$COMMIT_MSG" =~ \.$ ]]; then
    printf "BLOCKED: Message must not end with a period.\n" >&2
    exit 2
fi

exit 0