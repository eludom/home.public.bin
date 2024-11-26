#!/bin/bash
#
# ChatGPT Promt:
#
# write me a bash script that finds all the .org files under $HOME and
# hard links them to ~/orgfiles/, changing the "/" in paths to "__"

# This is bash, be safe
set -u
set -e

# use my info,warn,error aliases
source ~/lib/bash/bashutils.sh

# Define source and destination directories
source_dir="$HOME"
destination_dir="$HOME/orgfiles"

# Max hard links to make.  If I have more than 10k org files, there are problems.
MAXFILES=10000

# Create the destination directory if it doesn't exist
mkdir -p "$destination_dir"

# Find all .org and .csv files under $HOME and loop through them
find "$source_dir" -type f \( -name "*.org" -o -name "*.csv" \) | grep -v "$destination_dir" | head -$MAXFILES | while read -r original_file; do

    # Get the relative path by removing the source directory part
    relative_path=${original_file#"$source_dir"/}

    # Replace "/" in paths with "__"
    modified_relative_path1="${relative_path//\//__}"

    # Replace " " in paths with "_"
    modified_relative_path="${modified_relative_path1// /_}"


    # Construct the destination path
    local_link_to_original="$destination_dir/$modified_relative_path"


    # if local link and original file both exist and have different inode numbers,
    # remove the local link

    if [ -e "$original_file" ] && [ -e "$local_link_to_original" ] && [ "$(stat -c%i -- "$original_file")" != "$(stat -c%i -- "$local_link_to_original")" ]; then
        warn "inode number of original file ${original_file} and linked file have changed.  Removing linked file."
        \rm -f "$local_link_to_original"
    fi

    # if the target file exists, continue

    if [ -f "$local_link_to_original" ] ; then
        continue
    fi

    # Attempt to create a hard link to the destination
    if ln "$original_file" "$local_link_to_original" 2>/dev/null; then
        info "Linked file: $original_file -> $local_link_to_original"
    else
        warn "Failed to create a hard link for $original_file to $local_link_to_original"
    fi
done
