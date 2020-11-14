#! /bin/bash
# Allow ed to be usd to edit pipe.   If a filename is given, just edit that.
#
# Example:
#    cat FOO | e > BAR
#
#    e foo.txt
#
# TODO:
#    - Allow arguments (e.g. treat anything starting with a "-")
#      as an argument and pass that to both invocations below
#

FILE=${1:-""}

if [ "${FILE}" ]; then
    ed $FILE
else
    (F=$(mktemp) ; cat > $F ; ed $F </dev/tty >/dev/tty ; cat $F ; rm $F)
fi
