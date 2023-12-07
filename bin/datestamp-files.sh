#!/bin/bash
# for all files in one directory, rename the file adding it's mtime to the  filename
# so foo.txt becomes 2023-12-04-foo.txt

DIR=${1:-.}

# Use find to get all files in the directory
find $DIR -maxdepth 1 -type f | while read -r file
do
 # Use stat to get the modification time of the file
 mtime=$(stat -c %y "$file")

 # Format the modification time to YYYY-MM-DD
 formatted_mtime=$(date -d "$mtime" "+%Y-%m-%d-%H-%M-%S")

 # Rename the file by adding the modification time to the front of the filename
 mv "$file" "$DIR/${formatted_mtime}-$(basename "$file")"
done
