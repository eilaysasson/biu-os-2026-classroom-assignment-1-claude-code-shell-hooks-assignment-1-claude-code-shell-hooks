#!/bin/bash
# =============================================================================
# Pre-Hook 1: Command Firewall
# Purpose:    Block dangerous bash commands before execution.
# Input:      JSON on stdin: {"tool_name":"Bash","tool_input":{"command":"..."},...}
# Exit codes: 0 = allow, 2 = block (dangerous pattern matched)
# =============================================================================
#Resolve paths with the HOOK_DIR pattern.
# =============================================================================
HOOK_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_FILE="$HOOK_DIR/config/dangerous_patterns.txt"
# =============================================================================
#Read JSON from stdin. Extract tool_name and command.
# =============================================================================
INPUT="$(cat)"
TOOL_NAME=$(printf '%s' "$INPUT" | grep -o '"tool_name":"[^"]*"' | head -1 | sed 's/"tool_name":"//;s/"//')
COMMAND=$(printf '%s' "$INPUT" | grep -o '"command":"[^"]*"' | head -1 | sed 's/"command":"//;s/"//')
# =============================================================================
#If tool_name is not Bash, exit 0 — this hook only inspects shell commands.
# =============================================================================
if [ "$TOOL_NAME" != "Bash" ]; then
    exit 0
fi
# =============================================================================
#Load patterns from .claude/hooks/config/dangerous_patterns.txt. Each non-comment, non-empty line is a regex pattern.
# =============================================================================
# Check config file exists
if [ ! -f "$CONFIG_FILE" ]; then
    exit 0
fi
while IFS= read -r pattern; do
   # Skip comments and empty lines
      case "$pattern" in
          '#'*|'') continue ;;
      esac
      #Test the command against each pattern using grep -qE.
      if echo "$COMMAND" | grep -qE "$pattern"; then
         #On the first match:
         # Print an error to stderr naming the matched pattern.
         #Exit 2 to block.
              printf "BLOCKED: Command matches dangerous pattern '%s'. Please use a safer alternative.\n" "$pattern" >&2
              exit 2
          fi
      done < "$CONFIG_FILE"
# =============================================================================
#If no pattern matches, exit 0.
exit 0







