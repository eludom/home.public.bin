#! /bin/bash
# Do a quick status (git branch -vv) on one or more git repos
#
# Usage: gitstat [-f|-s] dir [dir...]
#
# -f - Fetch first
# -s - Short Status

set -e; 

fetch=false
status=false

function show_usage() {
    echo Usage: gitstat [-f] [-s] [dir[dir...]]
    exit 1
}

while [ ! -z "$1" ];do
   case "$1" in
        -h|--help)
          show_usage
          ;;
        -f|--fetch)
          fetch="true"
          ;;
        -s|--sleep)
          status="true"
          ;;
        *)
            if [[ "$1" =~ ^- ]]; then
                echo unknown flag $1
                show_usage
            else
                break
            fi
   esac
shift
done

ARGC=$#

if [ "$ARGC" == "0" ]; then
    set -- `pwd` "$@" # add pwd if no args
fi

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
