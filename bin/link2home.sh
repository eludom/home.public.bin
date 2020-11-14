#! /bin/bash
# Install files in current directory to $HOME in various ways.
#
# By default, create a directory in $HOME with the same name
# as the current directory, then symlink all files in this
# directory into the target directory
#
# Default directories are:

#    base directory   - $HOME
#    target directory - $HOME/`basename $PWD`
#    source directory - $PWD
##
# Usage: ${PROG} [options]
#
#    options
#
#      Modify the paths used
#
#      -p|--path=PATH     use PATH as base directory  (defalt $HOME)
#      -t|--tobase        link/copy files directly to base directory
#
#      Modify the copy/link behavior
#
#      -l|--linkdir       symlink this directory itself to base directory
#      -c|--copy          copy directory to target directory#
#      -r|--remove        remove old files
#
#      Change debugging and output
#
#      -d|--debug         debug output
#      -v|--verbose       verbose output
#

# - create a directory in $HOME with the same name as this directory
# - link all files in this directory in the new directory
# - exclude files listed in .link2home.ignore

set -e -u

# Helper functions
PROG=`basename "$0" | tr -d '\n'`

function info()  { echo ${PROG}\: info: "$@" 1>&2; }
function warn()  { echo ${PROG}\: warning: "$@" 1>&2; }
function error() { echo ${PROG}\: error: "$@" 1>&2; }
function debug() { [[ -v DEBUG ]] && echo ${PROG}\: debug: "$@" 1>&2 || true ; }
function die()   { echo ${PROG}\: fatal: "$@" 1>&2 && exit 1; }

#
# Command line parsing
#
function usage() {
    debug "in ${FUNCNAME[0]}"

    if [[ "$#" -gt 0 ]]; then
        warn $@
    fi

    cat <<END 1>&2
Usage: ${PROG} [options]

   options

     -c|--copy          copy directory to target directory
     -l|--linkdir       symlink this directory itself to base directory
     -p|--path=PATH     use PATH as base directory  (defalt $HOME)
     -r|--remove        remove old files
     -t|--tobase        link files directly to base directory

     -d|--debug         debug output
     -v|--verbose       verbose output

END
    exit 1
}

# globals variables

declare -A EXCLUSIONS

# parse global options

for i in "$@"
do
    case $i in
        -d|--debug)
            DEBUG=1
            d_flag="-d"
            shift # past argument with no value
            ;;
        -c|--copy)
            COPYDIR=1
            d_flag="-d"
            shift # past argument with no value
            ;;
        -l|--linkdir)
            LINKDIR=1
            d_flag="-d"
            shift # past argument with no value
            ;;
        -p=*|--PATH=*)
            TOPATH=1
            TO_PATH="${i#*=}"
            p_flag="-d"
            shift # past argument=value
            ;;
        -r|--remove)
            REMOVE=1
            # remove old files
            shift # past argument with no value
            ;;
        -t|--tobase)
            TOBASE=1
            d_flag="-d"
            shift # past argument with no value
            ;;
        -v|--verbose)
            VERBOSE=1
            v_flag="-v"
            shift # past argument with no value
            ;;
        -*|--*)
            usage "Unknown state option: $i"
            ;;
    esac
done

# Pull off command line args

if [ "$#" -ge 1 ]; then
    usage "No arguments expected"
fi

# Get abolute path to directory of current file
#REALDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
# use current directory
WHERE_AM_I=`pwd`

# Extract the directory name of this file
CURRENT_BASEDIR=`basename $WHERE_AM_I`


# Determine which directory to use as "HOME"

BASEDIR="${HOME}"

if [[ -v TOPATH ]]; then
    BASEDIR="${TO_PATH}"
fi

# Determine final destinaiton dir

if [[ -v TOBASE ]]; then
    FINAL_DIR="${BASEDIR}"
else
    FINAL_DIR="${BASEDIR}/${CURRENT_BASEDIR}"
fi

# if copying, just do it and stop

if [[ -v COPYDIR ]]; then
    [[ -v DEBUG ]] &&   echo cp -r -p ${WHERE_AM_I} ${FINAL_DIR}
    cp -r -p ${WHERE_AM_I} ${FINAL_DIR}
    exit 0
fi


# Link this directory into FINAL_DIR

if [[ -v LINKDIR ]]; then

    if [ -v REMOVE ]; then

        # never remove HOME !!!

        if [[ "${HOME}" == "${FINAL_DIR}" ]]; then
            [[ -v VERBOSE ]] &&  info not removing "${HOME}"
        else
          rm -f "${FINAL_DIR}"
          [[ -v VERBOSE ]] &&  info rm -f "${FINAL_DIR}"
        fi
    fi

    [[ -v VERBOSE ]] &&  info ln -s "${WHERE_AM_I}" "${FINAL_DIR}"
    ln -s "${WHERE_AM_I}"  "${FINAL_DIR}" || warn "Unable to link ${WHERE_AM_I}"

    exit 0
else
    # crate the directory name in $HOME if DNE
    mkdir -p "${FINAL_DIR}"
fi


#
#  Everything from here is releative to source directory
#


cd "${WHERE_AM_I}"

#
#  Ignore files listed in .link2home.ignore
#


if [ -f '.link2home.ignore' ]; then
    for exclude in `cat .link2home.ignore`; do
        EXCLUSIONS["${exclude}"]="${exclude}"
    done
fi

#
# symlink everything here to $HOME
#

debug linking files

#for file in * .[a-z]*; do
for file in * .[a-z0-9A-Z_\-]*; do

    SOURCE="${WHERE_AM_I}/${file}"
    TARGET="${FINAL_DIR}/${file}"

    [ -e "${file}" ] || continue

    if [ ${EXCLUSIONS["${file}"]+DNE} ]; then
        info skiping "${file}"
    else

        if [ -v REMOVE ]; then

            [[ -v VERBOSE ]] &&  info rm -f "${FINAL_DIR}/${file}"
            rm -f "${FINAL_DIR}/${file}"
        fi

        if [ -h "${TARGET}" ]; then
            [[ -v VERBOSE ]] &&  info "${TARGET}" already exists. Skipping.
        else
            [[ -v VERBOSE ]] &&  info ln -s "${SOURCE}" "${FINAL_DIR}"
            ln -s "${SOURCE}"  "${FINAL_DIR}" || warn "Unable to link ${SOURCE}"
        fi

    fi


done
