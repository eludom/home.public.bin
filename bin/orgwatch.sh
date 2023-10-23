#! /bin/bash
# link new .org files to ~/orgfiles and do git commint
#
# This should be run out of cron periodically
#
# Logs to /dev/tty and $LOGFILE

LOGFILE=/home/gmj/var/log/orgwatch.log

echo "--- Orgwatch `date` ---" |& tee /dev/tty >> ${LOGFILE}
/home/gmj/bin/orglinks.sh |& tee /dev/tty >> ${LOGFILE}
/home/gmj/bin/autocommit.sh |& tee /dev/tty >> ${LOGFILE}
echo |& tee /dev/tty >> ${LOGFILE}
