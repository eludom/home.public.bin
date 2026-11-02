#!/usr/bin/env bash
# Autocommit files in specified git dirs, log results
# Copyright (C) 2026 George Jones 
#
# Author: George Jones <gmj@pobox.com>
# Assisted-by: deepseek/deepseek-v4-flash-0731
# Maintainer: George Jones <gmj@pobox.com>
# URL: 
# Version: 0.3

set -euo pipefail

CONFIG_FILE="${GIT_BACKUP_CONFIG:-$HOME/etc/backup/gitdirs.txt}"
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

# Counters for summary
TOTAL_DIRS=0
CHANGED_DIRS=0
UNCHANGED_DIRS=0
WARNINGS=0
ERRORS=0

# Process one directory from the config file
process_dir() {
    local dir="$1"

    if [[ ! -d "$dir" ]]; then
        WARNINGS=$((WARNINGS + 1))
        msg="WARNING: Directory $dir does not exist. Skipping."
        log "$msg"
        info "$msg"   # keep warnings visible
        return
    fi

    if ! pushd "$dir" >/dev/null 2>&1; then
        WARNINGS=$((WARNINGS + 1))
        msg="WARNING: Cannot enter directory $dir. Skipping."
        log "$msg"
        info "$msg"
        return
    fi

    if ! git rev-parse --is-inside-work-tree &>/dev/null; then
        WARNINGS=$((WARNINGS + 1))
        msg="WARNING: $dir is not a valid git repository. Skipping."
        log "$msg"
        info "$msg"
        popd >/dev/null
        return
    fi

    # 🔍 Check for changes BEFORE printing anything
    local has_changes=false
    if $ADD_UNTRACKED; then
        if [[ -n "$(git status --porcelain)" ]]; then
            has_changes=true
        fi
    else
        if ! git diff --quiet || ! git diff --cached --quiet; then
            has_changes=true
        fi
    fi

    if [[ "$has_changes" == false ]]; then
        UNCHANGED_DIRS=$((UNCHANGED_DIRS + 1))
        popd >/dev/null
        return   # ✅ completely silent for unchanged dirs
    fi

    # Only here if there ARE changes
    CHANGED_DIRS=$((CHANGED_DIRS + 1))

    info ""
    info "Processing: $dir"
    log "\n----------------------------------------"
    log ""
    log "Processing: $dir"
    log "----------------------------------------"

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

    ADD_CMD="git add -u"
    if $ADD_UNTRACKED; then
        ADD_CMD="git add -A"
    fi

    log "[CHANGES DETECTED]"
    status_opts="--short"
    if ! $ADD_UNTRACKED; then status_opts="$status_opts --untracked-files=no"; fi

    git status $status_opts >> "$LOG_FILE"
    if $VERBOSE; then git status $status_opts; fi

    if $DRY_RUN; then
        log "[DRY-RUN] Would execute: $ADD_CMD"
        log "[DRY-RUN] Would execute: git commit -m 'Auto-backup: $(date)'"
        info "[DRY-RUN] Skipped committing changes for $dir"
    else
        info "Committing changes in $dir..."
        log "Running: $ADD_CMD"
        if ! add_output=$($ADD_CMD 2>&1); then
            ERRORS=$((ERRORS + 1))
            log "ERROR: '$ADD_CMD' failed in $dir"
            log "$add_output"
        else
            [[ -n "$add_output" ]] && log "$add_output"

            log "Running: git commit..."
            if commit_output=$(git commit -m "Auto-backup: $(date +'%Y-%m-%d %H:%M:%S')" 2>&1); then
                log "$commit_output"
                info "Successfully committed changes in $dir"
            else
                ERRORS=$((ERRORS + 1))
                log "ERROR: 'git commit' failed in $dir"
                log "$commit_output"
            fi
        fi
    fi

    popd >/dev/null
}
# Process directories
while IFS= read -r dir || [[ -n "$dir" ]]; do
    # Skip empty lines and comments
    [[ -z "$dir" || "$dir" =~ ^[[:space:]]*# ]] && continue

    # Expand tilde if present
    dir="${dir/#\~/$HOME}"

    TOTAL_DIRS=$((TOTAL_DIRS + 1))
    process_dir "$dir"
done < "$CONFIG_FILE"

# Summary
log "\n=== Summary ==="
log "Total directories: $TOTAL_DIRS"
log "Changed: $CHANGED_DIRS"
log "Unchanged: $UNCHANGED_DIRS"
log "Warnings: $WARNINGS"
log "Errors: $ERRORS"
log ""
log "=== Backup Finished: $(date) ==="
log "Log saved to: $LOG_FILE"

info ""
info "Summary: $TOTAL_DIRS dirs, $CHANGED_DIRS changed, $UNCHANGED_DIRS unchanged, $WARNINGS warning(s), $ERRORS error(s)"
info "Backup process finished. Log saved to: $LOG_FILE"

