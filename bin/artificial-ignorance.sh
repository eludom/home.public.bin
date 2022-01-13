#! /bin/bash
# Extract a stream of keywords from a file
#
# This is an applicaton of Marcus Ranum's principal of "Artificial Ignorance"
# http://www.ranum.com/security/computer_security/papers/ai/
#
# Usage: ai input-file term1 [term2 ...]
#
#   Input:
#      - input-file on the command line
#      - terms - one or more on the command line
#
#   Output:
#      - ai-TERM1.txt
#      - ai-TERM2.txt
#      - ...
#      - ai-TERMn.txt
#      - ai-leftovers.txt
# set -e
set -u

PREFIX=ai-
LEFTOVERS=ai-leftovers.txt
LEFTOVERS_TMP=/dev/null

INPUT=${1:-""}
OUTOUT=""

if [ "$INPUT" == "" ]; then
    echo Need file on command line
    exit 1
else
    shift
fi

for var in "$@"
do
    OUTPUT="${PREFIX}${var}.txt"
    PATTERN="${var}"
    LEFTOVERS_TMP="ai-leftovers-${var}.tmp"

    cat $INPUT | tee >(egrep -i $PATTERN > $OUTPUT) | (egrep -vi $PATTERN > $LEFTOVERS_TMP)


    INPUT=$LEFTOVERS_TMP
done

cp $LEFTOVERS_TMP $LEFTOVERS
rm -f ai-*.tmp || echo no leftovers
