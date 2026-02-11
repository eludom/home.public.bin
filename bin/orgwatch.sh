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

# List orphans
ORPHANS=$(find ~/orgfiles -name "*.org" -links 1)

if [ -n "$ORPHANS" ]; then
    echo "WARNING: Orphaned org files detected:" | tee -a "${LOGFILE}"
    echo "$ORPHANS" | tee -a "${ORPHAN_FILES}"
    # Optionally mail yourself

    TRASH=~/orgfiles/.trash/$(date +%Y-%m-%d)
    mkdir -p "$TRASH"

    find ~/orgfiles -maxdepth 1 -name "*.org" -links 1 -exec mv {} "$TRASH" \;

    # Git will see them as deleted
    git add -u
    git commit -m "Moved orphaned org files to trash"
fi

# Git cleanup if needed 
git gc --auto

