#!/bin/bash
# Count the files each directory in a heirarchy
#
# USAGE: count-files-in-directory.sh [DIR [FILETYPE]]

STARTDIR=${1:-.}
FILETYPE=${2:-""}

# Use find to get all directories in the directory structure
find $STARTDIR -type d -name \*${FILETYPE} | while read -r dir
do
 # Use wc to count the number of files in each directory
 num_files=$(find "$dir" -type f | wc -l)

 # Print the directory and the number of files
 echo "$num_files $dir"
done | sort -n -r
