#! /bin/bash
# link new .org files to ~/orgfiles and do git commint
#
# This should be run out of cron periodically
#
# Logs to /dev/tty and $LOGFILE

set -u; set -e; # this is bash.  be safe.

LOGFILE=/home/gmj/var/log/$(date +%Y-%m-%d)-orgwatch.log
touch "${LOGFILE}"

echo "--- Orgwatch $(date) ---" | tee -a "${LOGFILE}"
/home/gmj/bin/orglinks.sh | tee -a  "${LOGFILE}"
/home/gmj/bin/autocommit.sh | tee -a "${LOGFILE}"
echo | tee -a  >> "${LOGFILE}"

# Special directories and files 
ORGFILES=/home/gmj/orgfiles
DIARY_FILE="stow__home.private.org__Org__diary.org"
DIARY_DIFF=${ORGFILES}/$(date +%Y-%m-%d:%H:%M)-diary-diff.diff
PLANS_FILE="stow__home.private.org__Org__$(date +%Y).org"
PLANS_DIFF=${ORGFILES}/$(date +%Y-%m-%d:%H:%M)-$(date +%Y)-daily-plans-diff.diff

# default to orgfiles dir
cd "${ORGFILES}"

# diff the diary file
git diff HEAD~1 HEAD -- "${DIARY_FILE}" > "${DIARY_DIFF}"
# remove diffs if no changes
find "${DIARY_DIFF}"  -type f -size 0 -delete

# diff the paln file
git diff HEAD~1 HEAD -- "${PLANS_FILE}" > "${PLANS_DIFF}"
# remove diffs if no changes
find "${PLANS_DIFF}"  -type f -size 0 -delete

git add -- *.diff
# mail warning if more than N lines changed, more than M % changed or
# if there are lines longer than C characacters

# List all modified org files
git ls-files -m \*.org \*org_archive
# Add all modified files
git add -u
# Commit all changes org files
git commit -m "Added all org files"

