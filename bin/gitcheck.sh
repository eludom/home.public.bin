#! /bin/bash
# Do a quick status (git branch -vv) on one or more git repos
#
# Usage: gitstat [-f|-s] [dir [dir...]]
#
# -f - Fetch first
# -s - Short Status

set -e; set -u

ARGC=$#

if [ "$ARGC" == "0" ]; then
    set -- `pwd` "$@" # add pwd if no args
fi

fetch=false
status=false

for i in $* ; do

    if [ "$i" == "-f" ]; then
        fetch=true
        continue
    fi

    if [ "$i" == "-s" ]; then
        status=true
        continue
    fi

    if [ "$fetch" == "true" ]; then
        git fetch
    fi
    
    \pushd $i > /dev/null;
    echo $i;

    if [ "$status" == "true" ]; then
        git status -s
    else
        git branch -vv;
    fi
    echo;
    \popd > /dev/null;
done
