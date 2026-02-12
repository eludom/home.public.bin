#!/bin/bash
#
# orgwatch.sh - Backup, version, and maintain integrity of org files
#
# This script:
#   1. Hard links all .org/.csv/.org_archive files under $HOME to ~/orgfiles/
#      with flattened names using URL-style encoding (/ → %2F, space → %20, % → %25)
#   2. Generates timestamped diffs for critical files (diary, yearly plans)
#   3. Detects orphans (original deleted, link count = 1) → moves to .trash/
#   4. Detects stale links (original moved, link count > 1) → moves to .stale/
#      Note: Renamed files will have a new link created + old link moved to .stale/
#      This results in link count = 3 temporarily (harmless, just extra in .stale/)
#   5. Commits all changes to git for point-in-time recovery
#
# Symlink handling:
#   - Directory symlinks are followed (files inside are found and linked)
#   - File symlinks are followed (hard link points to the real file's inode)
#   - Cross-filesystem symlinks cannot be hard linked (warning logged)
#   - Broken symlinks are detected as stale
#
# Intended to be run periodically via cron.

set -u
set -e
set -o pipefail

# shellcheck disable=SC1090
if [[ -f ~/lib/bash/bashutils.sh ]]; then
    source ~/lib/bash/bashutils.sh
else
    # Fallback definitions if bashutils.sh not available
    info()  { echo "INFO: $*"; }
    warn()  { echo "WARN: $*" >&2; }
    error() { echo "ERROR: $*" >&2; exit 1; }
fi

#------------------------------------------------------------------------------
# Configuration (defaults, can be overridden by command-line options)
#------------------------------------------------------------------------------

ORGFILES="$HOME/orgfiles"
LOGDIR="$HOME/var/log"
LOGFILE="${LOGDIR}/$(date +%Y-%m-%d)-new-orgwatch.log"
MAXFILES=10000

# Critical files that get timestamped diffs (paths relative to $HOME)
CRITICAL_FILES=(
    "${HOME}/Org/diary.org"
    "${HOME}/Org/$(date +%Y).org"
)

# Runtime options
DRY_RUN=false
DEBUG=false
VERBOSE=false
QUIET=false
SKIP_GIT=false
MAX_STALE=0      # 0 = unlimited
MAX_ORPHANS=0    # 0 = unlimited

#------------------------------------------------------------------------------
# Usage
#------------------------------------------------------------------------------

usage() {
    cat <<'EOF'
Usage: orgwatch.sh [OPTIONS]

Backup, version, and maintain integrity of org files.

Options:
  -h, --help          Show this help message
  -n, --dry-run       Show what would be done without making changes
  -v, --verbose       Show more detailed output
  -q, --quiet         Suppress non-error output
  -d, --debug         Enable debug mode (set -x, very verbose)

  -m, --max-files N   Maximum files to process (default: 10000)
  --max-stale N       Stop after processing N stale files (for testing)
  --max-orphans N     Stop after processing N orphan files (for testing)

  --skip-git          Skip all git operations (for testing)
  --orgfiles DIR      Override orgfiles directory (default: ~/orgfiles)
  --logfile FILE      Override log file path

Examples:
  orgwatch.sh                     # Normal run
  orgwatch.sh -n -v               # Dry run with verbose output
  orgwatch.sh --max-files 10      # Process only first 10 files
  orgwatch.sh -d 2>&1 | head -50  # Debug first 50 lines of output

EOF
    exit 0
}

#------------------------------------------------------------------------------
# Argument parsing
#------------------------------------------------------------------------------

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                usage
                ;;
            -n|--dry-run)
                DRY_RUN=true
                shift
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            -q|--quiet)
                QUIET=true
                shift
                ;;
            -d|--debug)
                DEBUG=true
                VERBOSE=true
                set -x
                shift
                ;;
            -m|--max-files)
                MAXFILES="$2"
                shift 2
                ;;
            --max-stale)
                MAX_STALE="$2"
                shift 2
                ;;
            --max-orphans)
                MAX_ORPHANS="$2"
                shift 2
                ;;
            --skip-git)
                SKIP_GIT=true
                shift
                ;;
            --orgfiles)
                ORGFILES="$2"
                shift 2
                ;;
            --logfile)
                LOGFILE="$2"
                shift 2
                ;;
            *)
                echo "Unknown option: $1" >&2
                echo "Use --help for usage information" >&2
                exit 1
                ;;
        esac
    done

    # Validate numeric arguments
    if ! [[ "$MAXFILES" =~ ^[0-9]+$ ]]; then
        echo "Error: --max-files must be a number" >&2
        exit 1
    fi
}

#------------------------------------------------------------------------------
# Helpers
#------------------------------------------------------------------------------

log() {
    $QUIET && return 0
    echo "$(date '+%H:%M:%S') $*" | tee -a "$LOGFILE"
}

log_verbose() {
    $VERBOSE && log "$@" || true
}

log_debug() {
    $DEBUG && log "DEBUG: $*" || true
}

# Wrapper for commands that modify state
run() {
    if $DRY_RUN; then
        log "[DRY-RUN] $*"
        return 0
    fi
    "$@"
}

encode_path() {
    # URL-style percent encoding for unambiguous round-trip
    # Must encode % first (our escape char), then other special chars
    local path="$1"
    path="${path//%/%25}"      # % → %25 (must be first!)
    path="${path//\//%2F}"     # / → %2F
    path="${path// /%20}"      # space → %20
    echo "$path"
}

decode_path() {
    # Reverse the percent encoding
    # Decode in reverse order: space, /, then %
    local encoded="$1"
    encoded="${encoded//%20/ }"    # %20 → space
    encoded="${encoded//%2F//}"    # %2F → /
    encoded="${encoded//%25/%}"    # %25 → % (must be last!)
    echo "$HOME/$encoded"
}

ensure_git() {
    if $SKIP_GIT; then return 0; fi
    cd "$ORGFILES"
    if [[ ! -d .git ]]; then
        log "Initializing git repository"
        run git init --quiet .
        if ! $DRY_RUN; then
            echo "*.diff" >> .gitignore
            git add .gitignore
            git commit -m "Initialize orgfiles repository" --quiet
        fi
    fi
}

git_commit_if_changes() {
    if $SKIP_GIT; then return 1; fi
    local message="$1"
    cd "$ORGFILES"
    if [[ -n $(git status --porcelain) ]]; then
        run git add -A
        run git commit -m "$message" --quiet
        log "Committed: $message"
        return 0
    fi
    return 1
}

#------------------------------------------------------------------------------
# Phase 1: Create/update hard links
#------------------------------------------------------------------------------

link_org_files() {
    log "=== Linking org files ==="

    local linked=0 skipped=0 failed=0 symlinks=0

    # Track canonical paths we've already processed this run
    # (find -L can return same file via multiple symlink paths)
    declare -A seen_canonical

    # Use -L to follow symlinks (both directory and file symlinks)
    # This means:
    #   - Symlinked directories are descended into
    #   - Symlinked files are found (resolved to their target)
    #   - Paths returned are the logical path (via symlink), not resolved path
    #   - Hard links created will point to the real file's inode

    while IFS= read -r -d '' original; do
        # Skip if original vanished (race condition)
        [[ -e "$original" ]] || continue

        # Canonicalize path to avoid duplicates from symlinked directories
        # e.g., ~/org/foo.org and ~/Org/foo.org (where org->Org) become same canonical path
        local canonical
        canonical=$(readlink -f "$original")
        local relative="${canonical#"$HOME"/}"

        # Skip files outside $HOME (can happen with symlinks pointing elsewhere)
        if [[ "$relative" == "$canonical" ]]; then
            log_verbose "Skipping (outside HOME): $original → $canonical"
            continue
        fi

        # Skip if we've already processed this canonical path in this run
        if [[ -v seen_canonical["$canonical"] ]]; then
            log_debug "Skipping duplicate: $original (already processed as ${seen_canonical[$canonical]})"
            continue
        fi
        seen_canonical["$canonical"]="$original"

        local encoded
        encoded=$(encode_path "$relative")
        local link="$ORGFILES/$encoded"

        # Log if original path differs from canonical (symlink involved)
        if [[ "$original" != "$canonical" ]]; then
            log_verbose "Note: $original → $canonical"
            ((++symlinks))
        fi

        # If link exists with same inode, skip
        if [[ -e "$link" ]]; then
            if [[ "$(stat -c%i "$canonical")" == "$(stat -c%i "$link")" ]]; then
                log_debug "Unchanged: $relative"
                ((++skipped))
                continue
            fi
            # Inode mismatch - file was recreated, remove stale link
            log "Inode mismatch, relinking: $relative"
            run rm -f "$link"
        fi

        # Create hard link using canonical path
        local ln_err
        if ln_err=$(run ln "$canonical" "$link" 2>&1); then
            log "Linked: $relative"
            ((++linked))
        else
            # Diagnose the failure
            local orig_dev target_dev
            orig_dev=$(stat -c%d "$canonical" 2>/dev/null || echo "?")
            target_dev=$(stat -c%d "$ORGFILES")

            if [[ "$orig_dev" != "$target_dev" ]]; then
                log "WARN: Cross-filesystem ($orig_dev vs $target_dev): $relative"
            elif [[ -e "$link" ]]; then
                log "WARN: Link already exists: $relative"
            elif [[ ! -r "$canonical" ]]; then
                log "WARN: Cannot read original: $relative"
            else
                log "WARN: Failed to link: $relative"
                log "      ln error: $ln_err"
                log "      canonical: $canonical"
                log "      link: $link"
            fi
            ((++failed))
        fi

    done < <(find -L "$HOME" -path "$ORGFILES" -prune -o \
             -type f \( -name "*.org" -o -name "*.csv" -o -name "*.org_archive" \) \
             -print0 2>/dev/null | head -z -n "$MAXFILES")

    log "Linking complete: $linked new, $skipped unchanged, $failed failed"
    if ((symlinks > 0)); then
        log "  ($symlinks files accessed via symlinks)"
    fi
}

#------------------------------------------------------------------------------
# Phase 2: Generate diffs for critical files
#------------------------------------------------------------------------------

generate_critical_diffs() {
    log "=== Generating diffs for critical files ==="

    if $SKIP_GIT; then log "Skipping (git disabled)"; return 0; fi
    if $DRY_RUN; then log "Skipping (dry-run)"; return 0; fi

    cd "$ORGFILES"

    # Need at least 2 commits to diff
    if [[ $(git rev-list --count HEAD 2>/dev/null || echo 0) -lt 2 ]]; then
        log "Not enough commits for diffs yet"
        return
    fi

    for filepath in "${CRITICAL_FILES[@]}"; do
        # Strip $HOME prefix if present to get relative path
        local relpath="${filepath#"$HOME"/}"
        local encoded
        encoded=$(encode_path "$relpath")
        local difffile="${ORGFILES}/$(date +%Y-%m-%dT%H%M)-${encoded%.org}.diff"

        if [[ ! -f "$ORGFILES/$encoded" ]]; then
            log_verbose "Critical file not linked yet: $relpath"
            continue
        fi

        # Generate diff from last commit
        if git diff HEAD~1 HEAD -- "$encoded" > "$difffile" 2>/dev/null; then
            if [[ -s "$difffile" ]]; then
                log "Generated diff: $(basename "$difffile")"
            else
                rm -f "$difffile"
            fi
        else
            rm -f "$difffile" 2>/dev/null || true
        fi
    done
}

#------------------------------------------------------------------------------
# Phase 3: Detect and handle stale/orphan files
#------------------------------------------------------------------------------

# Stale vs Orphan:
#   - Orphan: link count = 1, original DELETED (only our backup remains) → .trash/
#   - Stale:  link count > 1, original MOVED/RENAMED (path changed) → .stale/
#
# We check both conditions together to route files correctly.

handle_stale_and_orphans() {
    log "=== Checking for stale and orphaned files ==="

    local trash_dir="$ORGFILES/.trash/$(date +%Y-%m-%d)"
    local stale_dir="$ORGFILES/.stale/$(date +%Y-%m-%d)"
    local orphan_count=0
    local stale_count=0

    for linkfile in "$ORGFILES"/*.org "$ORGFILES"/*.org_archive "$ORGFILES"/*.csv; do
        [[ -e "$linkfile" ]] || continue

        local basename
        basename=$(basename "$linkfile")
        local original
        original=$(decode_path "$basename")
        local link_count
        link_count=$(stat -c%h "$linkfile")

        log_debug "Checking: $basename (link_count=$link_count, original=$original)"

        # Check if original path still exists
        if [[ ! -e "$original" ]]; then
            if ((link_count == 1)); then
                # Check limit
                if ((MAX_ORPHANS > 0 && orphan_count >= MAX_ORPHANS)); then
                    log "Reached --max-orphans limit ($MAX_ORPHANS), stopping"
                    break
                fi
                # Orphan: original deleted, only our backup remains
                log "Orphan (original deleted): $basename"
                $DRY_RUN || mkdir -p "$trash_dir"
                run mv "$linkfile" "$trash_dir/"
                ((++orphan_count))
            else
                # Check limit
                if ((MAX_STALE > 0 && stale_count >= MAX_STALE)); then
                    log "Reached --max-stale limit ($MAX_STALE), stopping"
                    break
                fi
                # Stale: original moved/renamed, link count > 1 means file exists elsewhere
                # (A new link to the same inode was likely created under the new name)
                log "Stale (original moved/renamed): $basename (link count=$link_count, data preserved elsewhere)"
                $DRY_RUN || mkdir -p "$stale_dir"
                run mv "$linkfile" "$stale_dir/"
                ((++stale_count))
            fi
        fi
    done

    # Commit orphans
    if ((orphan_count > 0)); then
        log "WARNING: Moved $orphan_count orphaned files to .trash/"
        if ! $SKIP_GIT && ! $DRY_RUN; then
            cd "$ORGFILES"
            git add -A
            git commit -m "Moved $orphan_count orphans to .trash ($(date +%Y-%m-%d))" --quiet || true
        fi
    fi

    # Commit stale (separate commit for clarity)
    if ((stale_count > 0)); then
        log "Moved $stale_count stale links to .stale/"
        if ! $SKIP_GIT && ! $DRY_RUN; then
            cd "$ORGFILES"
            git add -A
            git commit -m "Moved $stale_count stale links to .stale ($(date +%Y-%m-%d))" --quiet || true
        fi
    fi
}

#------------------------------------------------------------------------------
# Phase 5: Commit all remaining changes
#------------------------------------------------------------------------------

commit_changes() {
    log "=== Committing changes ==="

    if $SKIP_GIT; then log "Skipping (git disabled)"; return 0; fi

    cd "$ORGFILES"

    # Show what's changed (verbose only)
    if $VERBOSE; then
        local new_files modified_files
        new_files=$(git ls-files --others --exclude-standard 2>/dev/null | wc -l)
        modified_files=$(git ls-files --modified 2>/dev/null | wc -l)
        log "New files: $new_files, Modified: $modified_files"
    fi

    git_commit_if_changes "Autocommit $(date '+%Y-%m-%d %H:%M')" || log "No changes to commit"

    # Periodic garbage collection
    if ! $DRY_RUN; then
        git gc --auto --quiet 2>/dev/null || true
    fi
}

#------------------------------------------------------------------------------
# Main
#------------------------------------------------------------------------------

main() {
    parse_args "$@"

    # Always create directories (even in dry-run, so cd and globs work)
    mkdir -p "$ORGFILES" "$LOGDIR"

    log "========================================"
    log "Orgwatch starting"
    if $DRY_RUN; then log "  *** DRY-RUN MODE - no changes will be made ***"; fi
    if $VERBOSE; then log "  ORGFILES=$ORGFILES"; fi
    if $VERBOSE; then log "  MAXFILES=$MAXFILES"; fi
    if $SKIP_GIT; then log "  *** Git operations disabled ***"; fi
    log "========================================"

    ensure_git
    link_org_files

    # Commit new links before generating diffs
    git_commit_if_changes "Added new org files $(date '+%Y-%m-%d %H:%M')" || true

    generate_critical_diffs
    handle_stale_and_orphans
    commit_changes

    log "Orgwatch complete"
    log ""
}

main "$@"
