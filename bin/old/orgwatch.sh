/bash
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
    declare -A seen_canonical

    while IFS= read -r -d '' original; do
        # Skip if original vanished (race condition)
        [[ -e "$original" ]] || continue

        # Canonicalize target path for hard-linking and duplicate checking
        local canonical
        canonical=$(readlink -f "$original")

        # Logical relative path (used for encoding the link filename)
        local relative="${original#"$HOME"/}"

        # Skip files outside $HOME
        if [[ "$relative" == "$original" ]]; then
            log_verbose "Skipping (outside HOME): $original"
            continue
        fi

        # Skip if we've already processed this canonical target in this run
        if [[ -v seen_canonical["$canonical"] ]]; then
            log_debug "Skipping duplicate target: $original (already processed as ${seen_canonical[$canonical]})"
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

        # If link exists with same inode as canonical target, skip
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

        # Create hard link pointing to the canonical target inode
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
        [[ -e "$filepath" ]] || continue

        # Resolve canonical path (handles Stow/symlinks)
        local canonical
        canonical=$(readlink -f "$filepath")
        local relpath="${canonical#"$HOME"/}"

        # Skip if canonical target lives outside $HOME
        if [[ "$relpath" == "$canonical" ]]; then
            log_verbose "Critical file outside HOME: $filepath → $canonical"
            continue
        fi

        local encoded
        encoded=$(encode_path "$relpath")
        local difffile="${ORGFILES}/$(date +%Y-%m-%dT%H%M)-${encoded%.org}.diff"

        if [[ ! -f "$ORGFILES/$encoded" ]]; then
            log_verbose "Critical file not linked yet: relpath $relpath , \"$ORGFILES/$encoded\" "
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


#
# Earlier interaction starts here
# 

## Diffs of critical files are not happening I think becuase the ~/orgfiles/ filename contains the full encoded
## symlink path (stow%2Fhome.private.org%2FOrg%2Fdiary.org) not the relpath
#
## 06:18:06 === Generating diffs for critical files ===
## 06:18:06 Critical file not linked yet: relpath Org/diary.org , /home/gmj/orgfiles/Org%2Fdiary.org 
## 06:18:06 Orgwatch complete
## 06:18:06 
## gmj@forum orgfiles [master] $ ls -lt *diary.org
## -rw-r--r-- 7 gmj gmj 186907 Sep  7 06:10 stow%2Fhome.private.org%2FOrg%2Fdiary.org
#
## How can I fix this?  I'd  prefer  to drop a few edits in 
#
## I fixed  generate_critical_diffs with changes you suggested earlier.
## Will this problem crop up anywhere else? 
#
## ``` reasoning
#**Analyzing Script Behavior**
#
#I'm currently examining how `readlink -f` handles symbolic links within the `orgwatch.sh` script. My focus is on understanding its interaction with symlinks like those generated by GNU Stow, specifically in contexts such as `~/Org/diary.org`, to pinpoint the root cause of the reported issue.
#
#**Tracing Path Discrepancies**
#
#I'm now tracing how `$original` and the `canonical` path, especially after `readlink -f`, interact within `link_org_files`. I'm focusing on how this difference, particularly with symlinks like those from Stow, could lead to mismatches when paths are encoded or decoded later.
#
#**Investigating Path Decoding**
#
#I'm now looking into how `$basename`, which is `stow%2F...%2Fdiary.org`, gets decoded into `$original` (`$HOME/stow/.../Org/diary.org`) within `handle_stale_and_orphans()`. I'm exploring how this process interacts with renamed or removed symlinks, especially when Stow manages the underlying targets.
#
#
#```# 
#
## Yes, this issue will crop up in **Phase 3 (`handle_stale_and_orphans`)** and affects **Git history continuity**.
#
## ---
#
## ### Where else this causes problems
#
## 1. **Broken Git History on Stow Structure Changes**
##    - If you move a Stow package (e.g., re-stowing from `stow/home.private.org` to `stow/common.org`), the canonical target changes even though the logical path (`~/Org/diary.org`) stayed the same.
##    - `orgwatch` will treat the old encoded path (`stow%2Fhome.private.org...`) as stale/orphaned and create a brand new file (`stow%2Fcommon.org...`). **This breaks Git history for that file** in `~/orgfiles/`.
#
## 2. **Phase 3: Stale/Orphan False Positives or Failures**
##    - `decode_path` decodes the filename back to `$HOME/stow/home.private.org/Org/diary.org`.
##    - If you delete the symlink `~/Org/diary.org` but leave the underlying Stow repository intact, `[[ -e "$original" ]]` checks the Stow target—**which still exists**. As a result, Phase 3 will **fail to detect the orphan**.
#
## 3. **Restoration Complexity**
##    - Backups in `~/orgfiles/` are named after the internal implementation detail (`stow%2F...`) rather than your logical directory layout (`Org%2Fdiary.org`).
#
## ---
#
#### Recommended Fix
#
## Instead of encoding the resolved `canonical` path, **encode the logical path** (relative to `$HOME`) when naming files in `~/orgfiles/`, while using `canonical` solely for `ln` and `stat` operations.
#
## #### 1. Update `link_org_files()`
## ```bash
## # Keep 'relative' based on 'original' (logical path)
## local relative="${original#"$HOME"/}"
## local encoded=$(encode_path "$relative")
## local link="$ORGFILES/$encoded"
#
## # Use canonical path for stat / ln target
## local canonical=$(readlink -f "$original")
#
## if [[ -e "$link" ]]; then
##     if [[ "$(stat -c%i "$canonical")" == "$(stat -c%i "$link")" ]]; then
##         ((++skipped))
##         continue
##     fi
##     run rm -f "$link"
## fi
#
## run ln "$canonical" "$link"
## ```
#
## #### 2. Why this fixes everything
## - **Diffs**: `CRITICAL_FILES` (`~/Org/diary.org`) maps cleanly to `Org%2Fdiary.org`.
## - **Git History**: Moving files within Stow won't create duplicate backup files as long as the logical `$HOME` path is unchanged.
## - **Orphan Detection**: `decode_path` decodes to `~/Org/diary.org`. If the symlink is gone, Phase 3 correctly identifies it as an orphan/stale link.
#
## Give me a version below with the changes applied.  Will running this now, with a bunch of legacy files using the old convention result in orphans or conflicts?
#
## ``` reasoning
#**Implementing Encoding Fix**
#
#I'm currently focused on integrating the recent update that modifies `link_org_files` to encode logical paths, a crucial step for accurate referencing. This adjustment aims to ensure seamless operation and improve the robustness of the linking mechanism within the system.
#
#**Assessing File Orphan Risk**
#
#My current focus is on understanding how the recent change to `link_org_files`, which now encodes logical paths instead of canonical ones, will interact with existing legacy files. I'm specifically analyzing the potential for orphans or conflicts to arise during the linking and subsequent cleanup phases when encountering files that adhere to the older convention.
#
#**Resolving Phantom Files**
#
#I'm currently analyzing a scenario where, due to the new logical path encoding and link counting, legacy files that are technically still linked might persist as unmanaged duplicates in `~/orgfiles/`. This happens because the underlying Stow target still exists, preventing the `handle_stale_and_orphans` function from identifying them for cleanup, essentially leaving "phantom" backups.
#
#**Resolving Legacy Duplicates**
#
#I've clarified that legacy files won't be automatically orphaned. They'll persist as duplicates because their original targets remain, bypassing the stale file check. A one-time migration or manual Git cleanup will be necessary for these lingering copies, ensuring a clean state after the encoding change.
#
#
#```# 
#
## ### Impact on Legacy Files
#
## Running this now **will not cause conflicts or automatically move legacy files to `.trash/` or `.stale/`**.
#
## Here is what happens:
## 1. **No Conflicts:** New links will be created with logical names (e.g., `Org%2Fdiary.org`). Because the filenames are different from the legacy ones (e.g., `stow%2F...`), there are no filename collisions.
## 2. **Legacy Files Linger:** Phase 3 checks `[[ ! -e "$original" ]]`. Because the decoded path of a legacy file (e.g., `~/stow/home.private.org/Org/diary.org`) still exists on disk, Phase 3 sees it as valid and **does not trash or stale it**.
## 3. **One-Time Cleanup Needed:** After running the updated script once, you can safely remove the old `stow%2F...` files from `~/orgfiles/` (they share the same inodes as the new links, so deleting the old link won't delete your data):
##    ```bash
##    cd ~/orgfiles
##    git rm stow%2F*
##    git commit -m "Clean up legacy canonical-path hard links"
##    ```
#
## ---
#
## ### Updated `link_org_files`
#
## Replace your existing `link_org_files` function with this updated version:
# 
## ...
#

#
#  Earlier interacton ends here
# 

After applying the changes recommeneded in the Earlier interaction
and deleteing all the stow%2Fhome* files by hand, I get

# 7:04:45 Linking complete: 983 new, 3495 unchanged, 0 failed
# 07:04:45   (2990 files accessed via symlinks)
# 07:04:47 Committed: Added new org files 2026-09-07 07:04
# 07:04:47 === Generating diffs for critical files ===
# 07:04:47 Critical file not linked yet: relpath stow/home.private.org/Org/diary.org , "/home/gmj/orgfiles/stow%2Fhome.private.org%2FOrg%2Fdiary.org" 
# 07:04:47 Critical file not linked yet: relpath stow/home.private.org/Org/2026.org , "/home/gmj/orgfiles/stow%2Fhome.private.org%2FOrg%2F2026.org" 
# 07:04:47 === Checking for stale and orphaned files ===
# 07:05:22 === Committing changes ===
# 07:05:23 New files: 0, Modified: 0
# 07:05:23 No changes to commit
# 07:05:23 Orgwatch complete
# 07:05:23 
# gmj@forum orgfiles [master] $ 
# gmj@forum orgfiles [master] $ llth *diff
# -rw-r--r-- 1 gmj gmj 676 Sep  7 06:29 2026-09-07T0629-stow%2Fhome.private.org%2FOrg%2F2026.diff
# -rw-r--r-- 1 gmj gmj 629 Sep  7 06:29 2026-09-07T0629-stow%2Fhome.private.org%2FOrg%2Fdiary.diff
# gmj@forum orgfiles [master] $ ^C
# gmj@forum orgfiles [master] $ po^C
# gmj@forum orgfiles [master] $ pwd
# /home/gmj/orgfiles
# gmj@forum orgfiles [master] $ ls -lt  stow%2F* | head
# -rw-r--r-- 7 gmj gmj 186912 Sep  7 07:03 stow%2Fhome.private.notes%2Fnotes%2F20260116T103011--diary__planning.org
# -rw-r--r-- 2 gmj gmj   4229 Sep  6 19:10 stow%2Fhome.private.notes%2Fnotes%2F20260906T173040--emacsconf-2026-submission__emacs_howto_public_writing.org

It re-linked the stow%2F files that I was told to delete and failed to generate new diff files (this was run after 7:00)

``` reasoning
**Revising Stow Strategy**

It seems my recent changes to `link_org_files` inadvertently restored unwanted `stow/*` files. The diff generation is now failing, indicating `relpath stow/home` is still not properly linked. I'll need to re-evaluate the linking logic to ensure these files are managed as intended.

**Investigating Stow Linking**

I've identified the root cause of the unwanted `stow/*` file linking. My `find -L` command was following symlinks, causing it to process both the symlink in `~/Org` and its real target within `$HOME/stow`, leading to duplicated and incorrectly encoded paths. I need to adjust `find`'s behavior.

**Fixing Find Behavior**

I've pinpointed the issue: my `find` command was recursively scanning the entire `$HOME` directory. This caused it to discover symlinks within `$HOME/stow` directly, in addition to the intended symlinks under `~/Org`. I need to refine `find`'s traversal to prevent this overlap and duplicate processing.

**Refining Find Logic**

The core problem stems from `find` encountering files within `$HOME/stow` directly, rather than only processing the symlinks I've explicitly created in `~/Org`. This leads to incorrect path resolutions when `generate_critical_diffs` attempts to match them, resulting in the "Critical file not linked yet" error even after linking attempts. I will adjust `find`'s scope.


```

The root cause is twofold:

1. **`find` scans Stow source directories under `$HOME` first:**
   `find` finds `~/stow/home.private.org/Org/diary.org` before `~/Org/diary.org`. Because `seen_canonical` deduplicates by inode, `stow/home.private.org/Org/diary.org` wins and gets linked as `stow%2F...`, while `~/Org/diary.org` is skipped as a duplicate.

2. **`generate_critical_diffs` resolves `readlink -f`:**
   `readlink -f` converted `~/Org/diary.org` to `~/stow/home.private.org/Org/diary.org`.

---

### Fix

#### 1. Prune Stow / dotfile repos from `find` in `link_org_files`:
Add `-path "$HOME/stow" -prune` (or whatever directory holds your Stow packages, e.g. `"$HOME/.dotfiles"`) to the `find` command so `find` only indexes the logical symlinked paths under `$HOME`:

```bash
    done < <(find -L "$HOME" \
             \( -path "$ORGFILES" -o -path "$HOME/stow" -o -path "$HOME/.stow" \) -prune -o \
             -type f \( -name "*.org" -o -name "*.csv" -o -name "*.org_archive" \) \
             -print0 2>/dev/null | head -z -n "$MAXFILES")
```

#### 2. Keep `filepath` logical in `generate_critical_diffs`:
Do **not** run `readlink -f` on `$filepath` when computing the relative path:

```bash
    for filepath in "${CRITICAL_FILES[@]}"; do
        [[ -e "$filepath" ]] || continue

        # Use logical path relative to $HOME (do NOT readlink -f)
        local relpath="${filepath#"$HOME"/}"
        local encoded
        encoded=$(encode_path "$relpath")
        local difffile="${ORGFILES}/$(date +%Y-%m-%dT%H%M)-${encoded%.org}.diff"

        if [[ ! -f "$ORGFILES/$encoded" ]]; then
            log_verbose "Critical file not linked yet: relpath $relpath , \"$ORGFILES/$encoded\" "
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
```

No.  This is not right.   Becase the "~/stow/..." files are the authoritative versions,
e.g. there may be files under ~/stow/ that I want to keep (working files, readmes, whole directories)
that are not symlniked back anywhere in ~/

``` reasoning
**Revising Stow Logic**

I'm adjusting the strategy for handling `$HOME/stow`. I now understand that files within `$HOME/stow` are considered the authoritative source and should not be pruned, even if they aren't symlinked back to `$HOME`. This ensures we preserve the original source files.

**Prioritizing Source Files**

I'm refining the logic for `~/stow`. My current thought is that `find` needs to prioritize locating files within `~/stow/` itself, even if they are already symlinked. This is crucial because the actual source files in `~/stow` are the definitive source, and their absence from `~/orgfiles/` due to processing the symlink first is causing critical file identification failures.

**Prioritizing Direct Paths**

I'm now focusing on how to handle inode collisions. My current direction is to assign a higher priority to logical paths directly under `$HOME` (excluding `$HOME/stow`). This ensures that shorter, more direct paths are preferred as the canonical representation when an inode exists in both a stow-managed location and a direct `$HOME` location.

**Prioritizing Direct Paths**

I'm now prioritizing direct paths outside of any stow directories. This means if an inode appears in a regular `$HOME` location and also within a stow directory, the non-stow path will be considered the primary one. This logic aims to resolve conflicts by favoring the more explicit, non-stowed representation.

**Resolving Symlink Conflicts**

I'm refining how symlink collisions are handled. If an existing symlink's source is within a `stow/` directory, but the new path is not, I'm prioritizing the new, non-stowed path. This involves unlinking the old symlink and creating a new one, ensuring the more direct representation takes precedence. Additionally, I've confirmed that files within `~/stow/` that aren't symlinked elsewhere are preserved.

**Prioritizing Non-Stow Paths**

I'm now refining the logic to ensure that non-stow paths are always preferred over stow-managed paths when resolving symlink conflicts for the same inode. This includes unlinking existing stow symlinks if a direct home directory path is encountered, and importantly, confirms that original files within `~/stow/` are always preserved.


```

To keep **all** files under `~/stow/` (even unlinked ones) while ensuring symlinked files prefer their logical `$HOME` path (e.g. `Org/diary.org` over `stow/home.private.org/Org/diary.org`), prioritize non-stow paths when duplicate inodes are encountered.

### 1. Update `link_org_files` (Path Priority Logic)

Replace duplicate detection in `link_org_files`:

```bash
        # Path priority: Non-stow logical paths override stow internal paths
        local is_new_stow=false is_old_stow=false
        [[ "$relative" =~ ^\.?stow/ ]] && is_new_stow=true

        if [[ -v seen_canonical["$canonical"] ]]; then
            local prev_relative="${seen_canonical["$canonical"]}"
            [[ "$prev_relative" =~ ^\.?stow/ ]] && is_old_stow=true

            if $is_old_stow && ! $is_new_stow; then
                # Upgrade link: remove old stow-encoded link in favor of logical path
                log "Upgrading path preference: $prev_relative -> $relative"
                local old_encoded
                old_encoded=$(encode_path "$prev_relative")
                run rm -f "$ORGFILES/$old_encoded"
            else
                log_debug "Skipping duplicate target: $original"
                continue
            fi
        fi
        seen_canonical["$canonical"]="$relative"
```

### 2. Update `generate_critical_diffs` (Use Logical Path)

Do not run `readlink -f` when resolving the relative path for critical diffs; use the exact logical path specified in `CRITICAL_FILES`:

```bash
generate_critical_diffs() {
    log "=== Generating diffs for critical files ==="

    if $SKIP_GIT; then log "Skipping (git disabled)"; return 0; fi
    if $DRY_RUN; then log "Skipping (dry-run)"; return 0; fi

    cd "$ORGFILES"

    if [[ $(git rev-list --count HEAD 2>/dev/null || echo 0) -lt 2 ]]; then
        log "Not enough commits for diffs yet"
        return
    fi

    for filepath in "${CRITICAL_FILES[@]}"; do
        [[ -e "$filepath" ]] || continue

        # Use logical relative path directly (do not canonicalize)
        local relpath="${filepath#"$HOME"/}"

        local encoded
        encoded=$(encode_path "$relpath")
        local difffile="${ORGFILES}/$(date +%Y-%m-%dT%H%M)-${encoded%.org}.diff"

        if [[ ! -f "$ORGFILES/$encoded" ]]; then
            log_verbose "Critical file not linked yet: relpath $relpath , \"$ORGFILES/$encoded\" "
            continue
        fi

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
```

### Result:
* Unlinked files in `~/stow/` will still be backed up as `stow%2F...`.
* Files symlinked to `~/Org/` will automatically upgrade to `Org%2F...` and remove the `stow%2F...` duplicates.
* Critical diffs will find `Org%2Fdiary.org` and generate successfully.

I think this is all just getting too complicated.  Let's start fresh.

``` reasoning
**Simplifying Solution Complexity**

I'm currently wrestling with the escalating complexity around path upgrades, duplicate validation, and the intricacies of Stow handling. The distinction between logical and canonical path resolution is proving to be a significant hurdle, and I'm prioritizing streamlining these aspects.

**Revising Logic Approach**

I'm now focusing on a complete reset for `orgwatch.sh`, aiming for a clean, robust design. My priority is to simplify the handling of path upgrades, duplicate validations, and Stow integration, specifically by distinguishing between logical and canonical path resolutions to streamline the backup process.

**Refining Archival Strategy**

I'm prioritizing a cleaner approach to archival by rethinking how we handle deduplication. Instead of complex on-the-fly inode checks, I'm exploring a simpler indexing method. My current focus is on separating the `find` operations for standard directories versus Stow-managed ones, aiming to process logical paths more effectively before dealing with canonical ones.


```

Here is a clean, simple approach that solves the Stow problem without complex logic:

### The Simple Two-Pass Strategy

1. **Pass 1 (Logical paths first):** Scan `$HOME` **excluding** `stow` and `orgfiles`.
   - Links `~/Org/diary.org` $\rightarrow$ `Org%2Fdiary.org`
   - Remembers the inode in `seen_inodes[inode]=1`
2. **Pass 2 (Unlinked Stow files):** Scan `$HOME/stow`.
   - If inode was already seen in Pass 1 $\rightarrow$ skip it.
   - If unlinked working file $\rightarrow$ links `stow/...` $\rightarrow$ `stow%2F...`
3. **Diffs:** Simply check `CRITICAL_FILES` using their logical paths (`Org/diary.org`).
4. **Stale/Orphans:** Decode filename $\rightarrow$ check if that exact path exists.

---

### Clean Code Implementation

```bash
#------------------------------------------------------------------------------
# Phase 1: Create/update hard links
#------------------------------------------------------------------------------

process_file() {
    local original="$1"
    declare -n seen_ref="$2"

    [[ -e "$original" ]] || return 0

    local canonical
    canonical=$(readlink -f "$original")
    local inode
    inode=$(stat -c%i "$canonical" 2>/dev/null) || return 0

    # Skip if we already backed up this inode under a preferred path
    if [[ -n "${seen_ref[$inode]:-}" ]]; then
        return 0
    fi
    seen_ref[$inode]=1

    local relative="${original#"$HOME"/}"
    local encoded
    encoded=$(encode_path "$relative")
    local link="$ORGFILES/$encoded"

    if [[ -e "$link" ]]; then
        if [[ "$(stat -c%i "$link")" == "$inode" ]]; then
            return 0  # Unchanged
        fi
        run rm -f "$link"
    fi

    run ln "$canonical" "$link" 2>/dev/null || true
}

link_org_files() {
    log "=== Linking org files ==="
    declare -A seen_inodes

    # Pass 1: Logical paths in $HOME (excluding stow and orgfiles)
    while IFS= read -r -d '' f; do
        process_file "$f" seen_inodes
    done < <(find -L "$HOME" \
             \( -path "$ORGFILES" -o -path "$HOME/stow" -o -path "$HOME/.stow" \) -prune -o \
             -type f \( -name "*.org" -o -name "*.csv" -o -name "*.org_archive" \) \
             -print0 2>/dev/null | head -z -n "$MAXFILES")

    # Pass 2: Unlinked files inside stow
    if [[ -d "$HOME/stow" ]]; then
        while IFS= read -r -d '' f; do
            process_file "$f" seen_inodes
        done < <(find -L "$HOME/stow" \
                 -type f \( -name "*.org" -o -name "*.csv" -o -name "*.org_archive" \) \
                 -print0 2>/dev/null | head -z -n "$MAXFILES")
    fi
}

#------------------------------------------------------------------------------
# Phase 2: Generate diffs for critical files
#------------------------------------------------------------------------------

generate_critical_diffs() {
    log "=== Generating diffs for critical files ==="
    if $SKIP_GIT || $DRY_RUN; then return 0; fi

    cd "$ORGFILES"
    [[ $(git rev-list --count HEAD 2>/dev/null || echo 0) -ge 2 ]] || return 0

    for filepath in "${CRITICAL_FILES[@]}"; do
        [[ -e "$filepath" ]] || continue

        local relpath="${filepath#"$HOME"/}"
        local encoded
        encoded=$(encode_path "$relpath")
        local difffile="${ORGFILES}/$(date +%Y-%m-%dT%H%M)-${encoded%.org}.diff"

        if [[ -f "$ORGFILES/$encoded" ]]; then
            if git diff HEAD~1 HEAD -- "$encoded" > "$difffile" 2>/dev/null; then
                [[ -s "$difffile" ]] || rm -f "$difffile"
            fi
        fi
    done
}
```

This ensures:
- Symlinked files always get backed up under their clean logical path (`Org%2Fdiary.org`).
- Unlinked files in `stow/` still get backed up.
- Diffs work predictably.
