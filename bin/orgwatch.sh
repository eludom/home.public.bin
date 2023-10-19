#! /bin/bash
# link new .org files to ~/orgfiles and do git commint
#
# This should be run out of cron periodically
#

echo "--- Orgwatch `date` ---"
/home/gmj/bin/orglinks.sh
/home/gmj/bin/autocommit.sh
