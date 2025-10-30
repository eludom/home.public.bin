#! /bin/bash
# link new .org files to ~/orgfiles and do git commint
#
# This should be run out of cron periodically
#
# Logs to /dev/tty and $LOGFILE

LOGFILE=/home/gmj/var/log/$(date +\%Y-\%m-%d)-orgwatch.log
touch $LOGFILE

echo "--- Orgwatch `date` ---" |& tee /dev/tty >> ${LOGFILE}
/home/gmj/bin/orglinks.sh |& tee /dev/tty >> ${LOGFILE}
/home/gmj/bin/autocommit.sh |& tee /dev/tty >> ${LOGFILE}
echo |& tee /dev/tty >> ${LOGFILE}

# diff diary
ORGFILES=/home/gmj/orgfiles
DIFF=${ORGFILES}/`date +%Y-%m-%d:%H:%M`-diary-diff.diff
cd $ORGFILES/

# diff the diary file
git diff HEAD~1 HEAD -- stow__home.private.org__Org__diary.org > $DIFF
# remove diffs if no changes
find $DIFF  -type f -size 0 -delete

git add *.diff
# mail warning if more than N lines changed, more than M % changed or
# if there are lines longer than C characacters

# List all modified org files
git ls-files -m \*.org \*org_archive
# Add all org files
git add *.org *org_archive
# Commit all changes org files
git commit -m "Added all org files"

