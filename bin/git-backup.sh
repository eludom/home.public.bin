#!/usr/bin/env bash
# Autocommit files in specified git dirs, log results
# Copyright (C) 2026 George Jones 
#
# Author: George Jones <gmj@pobox.com>
# Assisted-by: deepseek/deepseek-v4-flash-0731
# Maintainer: George Jones <gmj@pobox.com>
# URL: 
# Version: 0.2

set -euo pipefail

CONFIG_FILE="$HOME/etc/backup/gitdirs.txt"
LOG_DIR="$HOME/var/log"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
LOG_FILE="$LOG_DIR/git_backup_${TIMESTAMP}.log"

ADD_UNTRACKED=false
DRY_RUN=false
SILENT=false
VERBOSE=false

usage() {
    echo "Usage: $0 [OPTIONS]"
    echo "Options:"
    echo "  -a, --add-untracked  Include untracked files in the commit"
    echo "  -n, --dry-run        Show what would be done without making changes"
    echo "  -s, --silent         Suppress progress messages sent to stderr"
    echo "  -v, --verbose        Output log messages to stdout as well as logfile"
    echo "  -h, --help           Display this help message"
    exit 0
}

# Parse command line flags
while [[ $# -gt 0 ]]; do
    case "$1" in
        -a|--add-untracked) ADD_UNTRACKED=true; shift ;;
        -n|--dry-run) DRY_RUN=true; shift ;;
        -s|--silent|-q|--quiet) SILENT=true; shift ;;
        -v|--verbose) VERBOSE=true; shift ;;
        -h|--help) usage ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
done

# Logging function for logfile (and optionally stdout)
log() {
    local msg="$1"
    echo -e "$msg" >> "$LOG_FILE"
    if $VERBOSE; then
        echo -e "$msg"
    fi
}

# Informational messages output to stderr unless suppressed
info() {
    local msg="$1"
    if ! $SILENT; then
        echo -e "$msg" >&2
    fi
}

# Ensure log directory exists
mkdir -p "$LOG_DIR"
info "Starting git autocommit backup script..."
log "=== Git Backup Started: $(date) ==="
if $DRY_RUN; then log "*** DRY RUN MODE ENABLED ***"; fi
if $ADD_UNTRACKED; then log "*** INCLUDE UNTRACKED FILES ENABLED ***"; fi

if [[ ! -f "$CONFIG_FILE" ]]; then
    msg="ERROR: Config file not found at $CONFIG_FILE"
    log "$msg"
    info "$msg"
    exit 1
fi

info "Reading repositories from $CONFIG_FILE"

# Process directories
while IFS= read -r dir || [[ -n "$dir" ]]; do
    # Skip empty lines and comments
    [[ -z "$dir" || "$dir" =~ ^[[:space:]]*# ]] && continue

    # Expand tilde if present
    dir="${dir/#\~/$HOME}"

    info ""
    info "Processing: $dir"
    log "\n----------------------------------------"
    log ""
    log "Processing: $dir"
    log "----------------------------------------"

    if [[ ! -d "$dir" ]]; then
        msg="WARNING: Directory $dir does not exist. Skipping."
        log "$msg"
        info "$msg"
        continue
    fi

    # Subshell to handle cd safely
    (
        cd "$dir" || exit 1

        if ! git rev-parse --is-inside-work-tree &>/dev/null; then
            msg="WARNING: $dir is not a valid git repository. Skipping."
            log "$msg"
            info "$msg"
            exit 0
        fi

        # 1. Report untracked files
        untracked_org=$(git ls-files --others --exclude-standard '*.org')
        untracked_all=$(git ls-files --others --exclude-standard)
        
        org_count=0
        [[ -n "$untracked_org" ]] && org_count=$(echo "$untracked_org" | wc -l | tr -d ' ')
        
        all_count=0
        [[ -n "$untracked_all" ]] && all_count=$(echo "$untracked_all" | wc -l | tr -d ' ')

        info "Found $org_count untracked .org file(s) ($all_count total untracked file(s))"

        if [[ -n "$untracked_org" ]]; then
            log "[UNTRACKED .ORG FILES]:"
            log "$untracked_org"
        else
            log "[UNTRACKED .ORG FILES]: None"
        fi

        # Determine git add strategy
        ADD_CMD="git add -u"
        if $ADD_UNTRACKED; then
            ADD_CMD="git add -A"
        fi

        # 2. Check for changes based on the selected mode
        has_changes=false
        if $ADD_UNTRACKED; then
            if [[ -n $(git status --porcelain) ]]; then
                has_changes=true
            fi
        else
            if ! git diff --quiet || ! git diff --cached --quiet; then
                has_changes=true
            fi
        fi

        if ! $has_changes; then
            log "No matching changes to commit."
            info "No changes to commit in $dir."
            exit 0
        fi

        log "[CHANGES DETECTED]"
        status_opts="--short"
        if ! $ADD_UNTRACKED; then status_opts="$status_opts --untracked-files=no"; fi
        
        git status $status_opts >> "$LOG_FILE"
        if $VERBOSE; then git status $status_opts; fi

        # 3. Add files and commit
        if $DRY_RUN; then
            log "[DRY-RUN] Would execute: $ADD_CMD"
            log "[DRY-RUN] Would execute: git commit -m 'Auto-backup: $(date)'"
            info "[DRY-RUN] Skipped committing changes for $dir"
        else
            info "Committing changes in $dir..."
            log "Running: $ADD_CMD"
            add_output=$($ADD_CMD 2>&1)
            [[ -n "$add_output" ]] && log "$add_output"

            log "Running: git commit..."
            commit_output=$(git commit -m "Auto-backup: $(date +'%Y-%m-%d %H:%M:%S')" 2>&1)
            log "$commit_output"
            info "Successfully committed changes in $dir"
        fi
    )

done < "$CONFIG_FILE"

log "\n=== Backup Finished: $(date) ==="
log "Log saved to: $LOG_FILE"
info "Backup process finished. Log saved to: $LOG_FILE"
