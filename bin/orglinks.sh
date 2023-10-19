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

# Find all .org files under $HOME and loop through them
find "$source_dir" -type f -name "*.org" | grep -v "$destination_dir" | head -$MAXFILES | while read -r org_file; do
    # Get the relative path by removing the source directory part
    relative_path="${org_file#$source_dir/}"

    # Replace "/" in paths with "__"
    modified_relative_path1="${relative_path//\//__}"

    # Replace " " in paths with "_"
    modified_relative_path="${modified_relative_path1// /_}"


    # Construct the destination path
    destination_path="$destination_dir/$modified_relative_path"

    # if the target file exists, continue

    if [ -f $destination_path ] ; then
        continue
    fi

    # Attempt to create a hard link to the destination
    if ln "$org_file" "$destination_path" 2>/dev/null; then
        info "Linked file: $org_file -> $destination_path"
    else
        warn "Failed to create a hard link for $org_file to $destination_path"
    fi

done
