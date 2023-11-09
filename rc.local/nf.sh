# Define a funtion to list the newest file (nf)
#
# Usage: nf [#] [DIRECTORY]

# Use my utils, constants
source ~/lib/bash/bashutils.sh

nf() (

    # Parse args.  Alow count or dir a-positinaly.
    #
    # TODO add more standard arg parsing
    # TODO allow flags (e.g. --maxdepth|m=#)
    # TODO add --filename|-f flag.  No path included.
    #
    NUM=1
    DIR=$(pwd)

    if [[ $1 =~ ^[0-9]+$ ]]; then
        NUM=$1
        DIR=${2:-`pwd`}
    elif [[ $2 =~ ^[0-9]+$ ]]; then
        NUM=$2
        DIR=$1
    else
        DIR=${1:-`pwd`}
    fi

  if [ -d "$DIR" ]; then
    # Check if the argument is a valid directory
    \cd "$DIR" || die "$DIR is not a directory"
    # Use find to locate only files, not directories, and list them by modification time
    latest_files=$(find . -maxdepth 1 -type f  -printf "%T@\t${PWD}/%P\n" | sort -k1 -nr | head -n "${NUM}" | cut -f2-)

    if [ -n "$latest_files" ]; then
      echo "$latest_files"
    else
      warn "No files found in the $DIR"
    fi
  else
    info "Usage: $PROGNAME DIRECTORY"
    warn "$DIR is not a directory"
    return 1
  fi
)
