#!/bin/bash
# Wrapper for clipea that logs

command="/home/gmj/bin/clipea"
temp_logfile="/home/gmj/var/log/clipea.log.tmp"
logfile="/home/gmj/var/log/clipea-`date +%Y-%m`.log"
# Store the command line arguments
args="$@"

# Run the 'clipea' command with logging
script -q -f -e -c "$command $args" "$temp_logfile"

# Remove escape sequences and append to log
cat "$temp_logfile" | \
    sed -r \ 's/\x1B\[([0-9]{1,2}(;[0-9]{1,2})?)?[mGK]//g;s/\x0D//g' \
        >> $logfile

# Clean up
rm $temp_logfile
