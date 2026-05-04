#!/bin/bash
# =============================================================================
# Post-Hook 4: Auto-Backup
# Purpose:    After a file edit, create a timestamped backup with rotation.
# Input:      JSON on stdin: {"tool_name":"Edit","tool_input":{"file_path":"..."},...}
# Exit codes: 0 always (post-hooks should not block)
# Backups:    data/.backups/<basename>.<timestamp>
# Log:        data/session.log
# =============================================================================
# Resolve script and directory paths
HOOK_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_FILE="$HOOK_DIR/config/hooks.conf"
BACKUP_DIR="$HOOK_DIR/data/.backups"
LOG_DIR="$HOOK_DIR/data"

# Ensure backup directory exists
mkdir -p "$BACKUP_DIR"

# Read JSON input from stdin
INPUT="$(cat)"

# Extract file_path and session_id (default "default")
FILE_PATH=$(printf '%s' "$INPUT" | grep -o '"file_path":"[^"]*"' | head -1 | sed 's/"file_path":"//;s/"//')
SESSION_ID=$(printf '%s' "$INPUT" | grep -o '"session_id":"[^"]*"' | head -1 | sed 's/"session_id":"//;s/"//')
[ -z "$SESSION_ID" ] && SESSION_ID="default"

# Validate that file_path is provided and file exists
if [ -z "$FILE_PATH" ] || [ ! -f "$FILE_PATH" ]; then
    exit 0
fi

# Generate timestamp and filenames
TIMESTAMP=$(date +%Y-%m-%d_%H%M%S)
LOG_TIME=$(date "+%Y-%m-%d %H:%M:%S")
FILE_BASENAME=$(basename "$FILE_PATH")
BACKUP_FILENAME="$FILE_BASENAME.$TIMESTAMP"
BACKUP_FULL_PATH="$BACKUP_DIR/$BACKUP_FILENAME"

# 1. Perform the backup
cp "$FILE_PATH" "$BACKUP_FULL_PATH"

# 2. Log the operation
FILE_SIZE=$(wc -c < "$FILE_PATH")
SESSION_LOG="$LOG_DIR/session_$SESSION_ID.log"
printf "[%s] BACKUP %s -> .backups/%s (%s bytes)\n" \
    "$LOG_TIME" "$FILE_PATH" "$BACKUP_FILENAME" "$FILE_SIZE" >> "$SESSION_LOG"

# 3. Rotation Logic: Keep only MAX_BACKUPS versions per file
MAX_BACKUPS=$(grep "MAX_BACKUPS" "$CONFIG_FILE" | cut -d'=' -f2)
[ -z "$MAX_BACKUPS" ] && MAX_BACKUPS=5

# Find existing backups for this specific file, sorted by modification time (newest first)
# We look specifically for files starting with 'basename.'
EXISTING_BACKUPS=$(ls -t "$BACKUP_DIR/$FILE_BASENAME."* 2>/dev/null)
BACKUP_COUNT=$(echo "$EXISTING_BACKUPS" | wc -l)

if [ "$BACKUP_COUNT" -gt "$MAX_BACKUPS" ]; then
    # Identify files to delete (everything from position MAX_BACKUPS + 1 onwards)
    # tail -n +K starts outputting from the Kth line
    FILES_TO_REMOVE=$(echo "$EXISTING_BACKUPS" | tail -n +$((MAX_BACKUPS + 1)))
    rm -f $FILES_TO_REMOVE
fi

# Post-hooks must always exit with 0 to prevent blocking the main process
exit 0