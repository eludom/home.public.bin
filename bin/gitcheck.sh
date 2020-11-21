#! /bin/bash
# Do a quick status (git branch -vv) on one or more git repos
#
# Usage: gitstat [dir [dir...]]

set -e; set -u

ARGC=$#

if [ "$ARGC" == "0" ]; then
    set -- `pwd` "$@" # add pwd if no args
fi

for i in $* ; do
    \pushd $i > /dev/null;
    echo $i;
    git branch -vv;
    echo;
    \popd > /dev/null;
done
