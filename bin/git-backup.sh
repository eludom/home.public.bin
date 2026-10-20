#!/usr/bin/env bash
# Autocommit files in specified git dirs, log results
# 
# Copyright (C) 2026 George Jones 
#
# Author: George Jones <gmj@pobox.com>
# Assisted-by: deepseek/deepseek-v4-flash-0731
# Maintainer: George Jones <gmj@pobox.com>
# URL: 
# Version: 0.1

set -euo pipefail

source ~/lib/bash/bashutils.sh
 
CONFIG_FILE="$HOME/etc/backup/gitdirs.txt"
LOG_DIR="$HOME/var/log"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
LOG_FILE="$LOG_DIR/git_backup_${TIMESTAMP}.log"

DRY_RUN=false
VERBOSE=false

usage() {
    echo "Usage: $0 [OPTIONS]"
    echo "Options:"
    echo "  -n, --dry-run  Show what would be done without making changes"
    echo "  -v, --verbose  Output log messages to stdout as well as logfile"
    echo "  -h, --help     Display this help message"
    exit 0
}

# Parse command line flags
while [[ $# -gt 0 ]]; do
    case "$1" in
        -n|--dry-run) DRY_RUN=true; shift ;;
        -v|--verbose) VERBOSE=true; shift ;;
        -h|--help) usage ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

# Logging function
log() {
    local msg="$1"
    echo -e "$msg" >> "$LOG_FILE"
    if $VERBOSE; then
        echo -e "$msg"
    fi
}

# Ensure log directory exists
mkdir -p "$LOG_DIR"
log "=== Git Backup Started: $(date) ==="
if $DRY_RUN; then log "*** DRY RUN MODE ENABLED ***"; fi

if [[ ! -f "$CONFIG_FILE" ]]; then
    log "ERROR: Config file not found at $CONFIG_FILE"
    exit 1
fi

# Process directories
while IFS= read -r dir || [[ -n "$dir" ]]; do
    # Skip empty lines and comments
    [[ -z "$dir" || "$dir" =~ ^[[:space:]]*# ]] && continue

    # Expand tilde if present
    dir="${dir/#\~/$HOME}"

    log "\n----------------------------------------"
    log "Processing: $dir"
    log "----------------------------------------"

    if [[ ! -d "$dir" ]]; then
        log "WARNING: Directory does not exist. Skipping."
        continue
    fi

    # Subshell to handle cd safely
    (
        cd "$dir" || exit 1

        if ! git rev-parse --is-inside-work-tree &>/dev/null; then
            log "WARNING: $dir is not a valid git repository. Skipping."
            exit 0
        fi

        # 1. Report untracked .org files
        untracked_org=$(git ls-files --others --exclude-standard '*.org')
        if [[ -n "$untracked_org" ]]; then
            log "[UNTRACKED .ORG FILES]:"
            log "$untracked_org"
        else
            log "[UNTRACKED .ORG FILES]: None"
        fi

        # 2. Check for modified tracked files
        if git diff --quiet && git diff --cached --quiet; then
            log "No modified tracked files to commit."
            exit 0
        fi

        log "[MODIFIED FILES DETECTED]"
	git status --short --untracked-files=no >> "$LOG_FILE"
        if $VERBOSE; then git status --short --untracked-files=no; fi

        # 3. Add modified files and commit
        if $DRY_RUN; then
            log "[DRY-RUN] Would execute: git add -u"
            log "[DRY-RUN] Would execute: git commit -m 'Auto-backup: $(date)'"
        else
            log "Running: git add -u"
            add_output=$(git add -u 2>&1)
            [[ -n "$add_output" ]] && log "$add_output"

            log "Running: git commit..."
            commit_output=$(git commit -m "Auto-backup: $(date +'%Y-%m-%d %H:%M:%S')" 2>&1)
            log "$commit_output"
        fi
    )

done < "$CONFIG_FILE"

log "\n=== Backup Finished: $(date) ==="
log "Log saved to: $LOG_FILE"
info "Log saved to: $LOG_FILE" 
