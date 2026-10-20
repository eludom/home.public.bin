#! /bin/bash
# orgwatch.sh - Monitor, version, and maintain org file integrity
#
# This script is the second half of a two-part org file backup system:
#
#   1. orglinks.sh (run first) - Finds all .org files under $HOME and
#      hard links them to ~/orgfiles/, converting "/" in paths to "__"
#
#   2. This script (orgwatch.sh) - Performs maintenance and versioning:
#      - Creates timestamped .diff files for critical files (diary, plans)
#      - Detects orphaned .org files (link count = 1, meaning the
#        original was deleted) and moves them to a dated trash folder
#      - Commits all changes to git for point-in-time recovery
#      - Performs periodic git garbage collection
#
# The result is a complete version history of all org files with the
# ability to recover any file at any point in time, detect accidental
# deletions, and track changes to critical files.
#
# Intended to be run periodically via cron.
#
# Logs to /dev/tty and $LOGFILE

set -u; set -e; # this is bash.  be safe.

LOGFILE=/home/gmj/var/log/$(date +%Y-%m-%d)-orgwatch.log
touch "${LOGFILE}"

echo "--- Orgwatch $(date) ---" | tee -a "${LOGFILE}"
/home/gmj/bin/orglinks.sh | tee -a  "${LOGFILE}"
/home/gmj/bin/autocommit.sh | tee -a "${LOGFILE}"
echo | tee -a "${LOGFILE}"

# Special directories and files 
ORGFILES=/home/gmj/orgfiles
DIARY_FILE="stow__home.private.org__Org__diary.org"
DIARY_DIFF=${ORGFILES}/$(date +%Y-%m-%dT%H%M)-diary-diff.diff
PLANS_FILE="stow__home.private.org__Org__$(date +%Y).org"
PLANS_DIFF=${ORGFILES}/$(date +%Y-%m-%dT%H%M)-$(date +%Y)-daily-plans-diff.diff
ORPHAN_FILES=${ORGFILES}/$(date +%Y-%m-%dT%H%M)-orphans.txt

# default to orgfiles dir
cd "${ORGFILES}"

# # diff the diary file
# git diff HEAD~1 HEAD -- "${DIARY_FILE}" > "${DIARY_DIFF}"
# # remove diffs if no changes
# find "${DIARY_DIFF}"  -type f -size 0 -delete
# [ -s "${DIARY_DIFF}" ] && git add "${DIARY_DIFF}"

# # diff the paln file
# git diff HEAD~1 HEAD -- "${PLANS_FILE}" > "${PLANS_DIFF}"
# # remove diffs if no changes
# find "${PLANS_DIFF}"  -type f -size 0 -delete
# [ -s "${PLANS_DIFF}" ] && git add "${PLANS_DIFF}"


# # mail warning if more than N lines changed, more than M % changed or
# # if there are lines longer than C characacters

# # List all modified org files
# git ls-files -m \*.org \*org_archive
# # Add all modified files
# git add -u
# # Commit all changes org files
# git commit -m "Added all org files" || true

# # Clean up stale links (original file was renamed/moved)
# echo "Checking for stale links..." | tee -a "${LOGFILE}"
# STALE_DIR="${ORGFILES}/.stale/$(date +%Y-%m-%d)"

# for linkfile in "${ORGFILES}"/*.org "${ORGFILES}"/*.org_archive; do
#     [ -e "$linkfile" ] || continue  # handle empty glob
    
#     # Decode filename back to original path
#     basename=$(basename "$linkfile")
#     original_path="$HOME/$(echo "$basename" | sed 's/__/\//g')"
    
#     # If original doesn't exist, move to stale dir
#     if [ ! -e "$original_path" ]; then
#         echo "Moving stale link: $basename (original: $original_path)" | tee -a "${LOGFILE}"
#         mkdir -p "$STALE_DIR"
#         mv "$linkfile" "$STALE_DIR/"
#     fi
# done

# # Commit stale file moves if any occurred
# if [ -d "$STALE_DIR" ]; then
#     git add -u
#     git commit -m "Moved stale links to .stale" || true
# fi

# # List orphans
# ORPHANS=$(find ~/orgfiles -name "*.org" -links 1  ! -path '/home/gmj/orgfiles/.trash/*')

# if [ -n "$ORPHANS" ]; then
#     echo "WARNING: Orphaned org files detected:" | tee -a "${LOGFILE}"
#     echo "$ORPHANS" | tee -a "${ORPHAN_FILES}"
#     # Optionally mail yourself

#     TRASH=~/orgfiles/.trash/$(date +%Y-%m-%d)
#     mkdir -p "$TRASH"

#     find ~/orgfiles -maxdepth 1 -name "*.org" -links 1 -exec mv {} "$TRASH" \;

#     # Git will see them as deleted
#     git add -u
#     git commit -m "Moved orphaned org files to trash"
# fi

# # Git cleanup if needed 
# git gc --auto


# Does this handle?
# 3. **No cleanup of truly orphaned links** - If you rename/move an original file, you'll end up with two links in `orgfiles/` (old orphan + new link). The orphan detection in orgwatch.sh handles deletions, but renames create duplicates.

# If not, would it be appropriate to do this as part of orgwatch.sh ?
  
#   - Iterates through all files in $destination_dir  
#   - Decodes each filename back to the original path                                                                                                           
#   - Checks if that original path still exists                                                                                                                 
#   - Removes the link if the original is gone   

# Yes, that would be appropriate to add to orgwatch.sh. Here's the addition:

# ```bash
# # Clean up stale links (original file was renamed/moved)
# echo "Checking for stale links..." | tee -a "${LOGFILE}"
# for linkfile in "${ORGFILES}"/*.org "${ORGFILES}"/*.org_archive; do
#     [ -e "$linkfile" ] || continue  # handle empty glob
    
#     # Decode filename back to original path
#     basename=$(basename "$linkfile")
#     original_path="$HOME/$(echo "$basename" | sed 's/__/\//g')"
    
#     # If original doesn't exist, remove the stale link
#     if [ ! -e "$original_path" ]; then
#         echo "Removing stale link: $basename (original: $original_path)" | tee -a "${LOGFILE}"
#         rm "$linkfile"
#     fi
# done
# ```

# This should go **before** the orphan detection block, since:

# 1. Stale links (original renamed/moved) will have link count > 1 if the new location was already linked
# 2. But they might have link count = 1 if the inode was reused or file was moved outside `$HOME`
# 3. Running this first cleans up the obvious cases, then orphan detection catches true deletions

# The distinction:
# - **Stale link**: filename decodes to a path that doesn't exist (rename/move)
# - **Orphan**: file exists but link count = 1 (original deleted, only backup remains)

# How about moving to ~/.stale, paraell to .trash ?

# Yes, that's cleaner and more consistent. Here's the updated block:

# ```bash
# # Clean up stale links (original file was renamed/moved)
# echo "Checking for stale links..." | tee -a "${LOGFILE}"
# STALE_DIR="${ORGFILES}/.stale/$(date +%Y-%m-%d)"

# for linkfile in "${ORGFILES}"/*.org "${ORGFILES}"/*.org_archive; do
#     [ -e "$linkfile" ] || continue  # handle empty glob
    
#     # Decode filename back to original path
#     basename=$(basename "$linkfile")
#     original_path="$HOME/$(echo "$basename" | sed 's/__/\//g')"
    
#     # If original doesn't exist, move to stale dir
#     if [ ! -e "$original_path" ]; then
#         echo "Moving stale link: $basename (original: $original_path)" | tee -a "${LOGFILE}"
#         mkdir -p "$STALE_DIR"
#         mv "$linkfile" "$STALE_DIR/"
#     fi
# done

# # Commit stale file moves if any occurred
# if [ -d "$STALE_DIR" ]; then
#     git add -u
#     git commit -m "Moved stale links to .stale" || true
# fi
# ```

# Now you have a parallel structure:
# - `.trash/` - orphans (original deleted, backup preserved)
# - `.stale/` - stale links (original moved/renamed, link outdated)

# Both dated, both tracked by git.
