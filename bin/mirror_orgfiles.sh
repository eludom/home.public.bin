#!/usr/bin/env bash
#
# mirror-orgfiles.sh
# Mirror .org files from $HOME into ~/orgfiles and commit to git.
# Supports --only DIR to limit the scan to one directory (recursive).

set -euo pipefail
export PATH="/usr/local/bin:/usr/bin:/bin:$PATH"

VERBOSE=false
DEBUG=false
DRY_RUN=false
ONLY_DIR=""
LOG_DIR=""

usage() {
    cat <<EOF
Usage: $0 [OPTIONS]

Mirror .org files found under \$HOME into ~/orgfiles and commit to git.

Options:
  -h, --help          Show this help and exit
  -d, --debug         Enable debug tracing
  -n, --dry-run       Print actions without making changes
  -v, --verbose       Print every action
  -o, --only DIR      Only mirror .org files under DIR (recursively)
  --log [DIR]         Write a diff file for each commit to DIR, or to cwd
EOF
    exit 0
}

# Parse options
while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help) usage ;;
        -d|--debug) DEBUG=true ;;
        -n|--dry-run) DRY_RUN=true ;;
        -v|--verbose) VERBOSE=true ;;
        -o|--only)
            if [[ $# -lt 2 ]]; then
                echo "Error: $1 requires an argument" >&2
                exit 1
            fi
            ONLY_DIR="$2"
            shift
            ;;
        --log|-log)
            # Optional argument: consume next arg only if it exists and is a directory.
            if [[ $# -ge 2 && "$2" != -* && -d "$2" ]]; then
                LOG_DIR="$2"
                shift
            else
                LOG_DIR="$PWD"
            fi
            ;;
        *) echo "Unknown option: $1" >&2; usage ;;
    esac
    shift
done

[[ $DEBUG == true ]] && set -x

# Configuration
MY_HOME="$HOME"
ORG_DIR="$MY_HOME/orgfiles"
HOME_REAL="$(realpath -m -- "$MY_HOME")"
ORG_DIR_REAL="$(realpath -m -- "$ORG_DIR")"

# Search root: --only directory or $HOME
if [[ -n "$ONLY_DIR" ]]; then
    SEARCH_ROOT="$(realpath -m -- "$ONLY_DIR")"
else
    SEARCH_ROOT="$HOME_REAL"
fi

# Determine which paths in ~/orgfiles should be pruned.
# Empty prefix = prune everything stale; non-empty = prune only under that prefix.
if [[ -z "$ONLY_DIR" || "$SEARCH_ROOT" == "$HOME_REAL" ]]; then
    PRUNE_PREFIX=""
elif [[ "$SEARCH_ROOT" == "$HOME_REAL"/* ]]; then
    PRUNE_PREFIX="${SEARCH_ROOT#$HOME_REAL/}"
else
    PRUNE_PREFIX="external/${SEARCH_ROOT#/}"
fi

ensure_git_repo() {
    [[ $DRY_RUN == true ]] && return
    if [[ ! -d "$ORG_DIR/.git" ]]; then
        echo "Initializing git repository in $ORG_DIR"
        mkdir -p "$ORG_DIR"
        git -C "$ORG_DIR" init
    fi
}

collect_and_link() {
    local p rp rel dest stale dir
    declare -A seen=()
    declare -A keep=()

    while IFS= read -r -d '' p; do
        rp="$(realpath -m -- "$p" 2>/dev/null)" || continue

        # Never mirror from the orgfiles directory itself
        if [[ "$rp" == "$ORG_DIR_REAL" || "$rp" == "$ORG_DIR_REAL"/* ]]; then
            continue
        fi

        [[ -f "$rp" ]] || continue

        # In --only mode, skip files outside the chosen search root
        if [[ -n "$ONLY_DIR" && "$rp" != "$SEARCH_ROOT" && "$rp" != "$SEARCH_ROOT"/* ]]; then
            continue
        fi

        # Deduplicate files reachable through multiple paths
        if [[ -n "${seen[$rp]+_}" ]]; then
            continue
        fi
        seen["$rp"]=1

        # Destination path relative to $HOME
        if [[ "$rp" == "$HOME_REAL" || "$rp" == "$HOME_REAL"/* ]]; then
            rel="${rp#$HOME_REAL/}"
        else
            rel="external/${rp#/}"
        fi

        dest="$ORG_DIR/$rel"
        keep["$rel"]=1

        # Already hardlinked?
        if [[ -e "$dest" && "$rp" -ef "$dest" ]]; then
            [[ $VERBOSE == true ]] && echo "current (hardlink): $rel"
            continue
        fi

        if [[ $DRY_RUN == true ]]; then
            echo "would install: $rp -> $rel"
            continue
        fi

        mkdir -p "$(dirname "$dest")"
        if ln -f -- "$rp" "$dest" 2>/dev/null; then
            [[ $VERBOSE == true ]] && echo "hardlinked: $rel"
        else
            rm -f -- "$dest"
            cp -p -- "$rp" "$dest"
            [[ $VERBOSE == true ]] && echo "copied: $rel"
        fi
    done < <(
        find -L "$SEARCH_ROOT" -xdev \
            \( -path "$ORG_DIR" -o -path "$ORG_DIR_REAL" -o -name .git \) -prune -o \
            -type f -name '*.org' -print0 2>/dev/null
    )

    # Stale cleanup: only within the current --only scope, or everywhere on full runs.
    if [[ $DRY_RUN == true ]]; then
        return
    fi

    while IFS= read -r -d '' stale; do
        rel="${stale#$ORG_DIR/}"

        if [[ -n "$PRUNE_PREFIX" ]]; then
            if [[ "$rel" != "$PRUNE_PREFIX" && "$rel" != "$PRUNE_PREFIX"/* ]]; then
                continue
            fi
        fi

        if [[ -z "${keep[$rel]+_}" ]]; then
            echo "removing stale: $rel"
            rm -f -- "$stale"

            # Remove empty parent directories up to ~/orgfiles
            dir="$(dirname "$stale")"
            while [[ "$dir" != "$ORG_DIR" && "$dir" != "/" ]]; do
                rmdir "$dir" 2>/dev/null || break
                dir="$(dirname "$dir")"
            done
        fi
    done < <(find -L "$ORG_DIR" -type f -name '*.org' -print0 2>/dev/null)
}

commit_changes() {
    [[ $DRY_RUN == true ]] && return

    if git -C "$ORG_DIR" diff --cached --quiet; then
        [[ $VERBOSE == true ]] && echo "No changes to commit"
        return
    fi

    # Save a full diff of the staged changes, if requested
    if [[ -n "$LOG_DIR" ]]; then
        local stamp diff_file
        stamp="$(date +%Y%m%d-%H%M%S)"
        diff_file="$LOG_DIR/orgfiles-diff-$stamp.diff"
        git -C "$ORG_DIR" diff --cached --no-ext-diff > "$diff_file"
        [[ $VERBOSE == true ]] && echo "diff saved: $diff_file"
    fi

    git -C "$ORG_DIR" \
        -c user.name="orgfiles" \
        -c user.email="orgfiles@$(hostname)" \
        commit -m "Update .org files $(date +'%Y-%m-%d %H:%M:%S')"
}

ensure_git_repo
collect_and_link
commit_changes
