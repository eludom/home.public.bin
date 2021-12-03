#! /bin/bash
# Download a file and it's sha256 checksum and validate
#
# Usage: check-sha256-and-download.sh FILE_URL CHECKSUM_URL
#
# Output:
#   - The name of the validated file on stdout (to allow use in further scripting)
#
# Errors:
#   - Errors, warnings on stderr
#   - non-zero exit status on errors.

# This is bash.  Be safe out there.
set -e; set -u 

# Helper functions
PROG=`basename "$0" | tr -d '\n'`
function info()  { echo `date +%c` ${PROG}\: info: "$@" 1>&2; }
function warn()  { echo `date +%c` ${PROG}\: warning: "$@" 1>&2; }
function error() { echo `date +%c` ${PROG}\: error: "$@" 1>&2; }
function debug() { [[ -v DEBUG ]] && echo `date +%c` ${PROG}\: debug: "$@" 1>&2 || true ; }
function die()   { echo `date +%c` ${PROG}\: fatal: "$@" 1>&2 && exit 1; }

USAGE="$PROG FILE_URL CHECKSUM_URL"

if [[ "$#" -lt 1 ]]; then
    warn "Missing FILE_URL"
    die "Uaage: $USAGE"
else
    FILE_URL="$1"                   # "https://download.edge.mysocket.io/linux_arm64/mysocketctl"
    FILE="`basename $1`"

fi

if [[ "$#" -lt 2 ]]; then
    warn "Missing CHECKSUM_URL"
    die "Uaage: $USAGE"

else
    CHECKSUM_URL="$2"               # "https://download.edge.mysocket.io/linux_arm64/sha256-checksum.txt"
    CHECKSUM_FILE="`basename $2`"
fi

CURL="curl -s -S"
SUM="sha256sum --quiet -c"

# Always get latest checksum
${CURL} "${CHECKSUM_URL}" > "${CHECKSUM_FILE}" \
     || die "Failure to download mysocket sha checksum"

# Check existing file against checksum or download
if [ -f "${FILE}" ]; then
    info "Allready have file."
    # file already exists, check it, downlaod if failed
    echo "`cat ${CHECKSUM_FILE}` ${FILE}" | ${SUM} -c \
        || info "Checksum failed.   Downloading." \
            && ${CURL} "${FILE_URL}" > "${FILE}" \
                    || die "Failure to download"
else
    info "File not found.  Downloading."
    ${CURL} "${FILE_URL}" > "${FILE}" \
                    || die "Failure to download"
fi

# Final check of checksum
echo "`cat ${CHECKSUM_FILE}` ${FILE}" | ${SUM} \
    || die "Checksum failed.   Downloading." \

info "$FILE validated"           
echo $FILE

