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
#      - terms - one or more on the command line.
#
#                terms can have "|" to match more than one term.
#
#                If there is a "|", the first term will be used
#                as the output file name.
#
#                Note if you want the
#                output to have a particualr name, use it as
#                the first term, it may not actually match in grep.
#
#   Output:
#      - ai-TERM1.txt
#      - ai-TERM2.txt
#      - ...
#      - ai-TERMn.txt
#      - ai-leftovers.txt
#
# Example
#
# I wrapped this in a shell script as follows to write a report.
#
#    ! /bin/bash
#    artificial-ignorance.sh completd-only.org \
#    'research-projects|clustering|heatmaps' \
#    'external|USENIX' \
#    'products|firewall' \
#    'development|lint|make|python' \
#
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
    PATTERN="${var}"
    # allow patterns of A|B|C, use first element as name
    FIRST_ELEMENT=`echo $PATTERN | sed -e 's/|.*//'`
    OUTPUT="${PREFIX}${FIRST_ELEMENT}.txt"
    LEFTOVERS_TMP="ai-leftovers-${FIRST_ELEMENT}.tmp"

    cat $INPUT | tee >(egrep -i "$PATTERN" > $OUTPUT) | (egrep -vi "$PATTERN" > $LEFTOVERS_TMP)


    INPUT=$LEFTOVERS_TMP
done

cp $LEFTOVERS_TMP $LEFTOVERS
rm -f ai-*.tmp || echo no leftovers
