#!/bin/bash
# Use zip to encrypt all single files CRYPTDIR with PASSWORD

# this is bash; be safe
set -e
set -u

# Set up logging functions (die, warn, info ...)
source $HOME/lib/bash/bashutils.sh

# Get the encryption password from the CRYPTDIR_PASS environment variable
password=${CRYPTDIR_PASS:-"NONE"}

# Check if password is defined
if [ $password == "NONE" ]; then
  die "ERROR: CRYPTDIR_PASS environment variable not defined"
fi

cryptdir=${CRYPTDIR:-"NONE"}

# Check if password is defined
if [ $cryptdir == "NONE" ]; then
  die "ERROR: CRYPTDIR environment variable not defined"
fi

cd $cryptdir || die "Can't cd to $cryptdir"
info "encrypting files in $cryptdir"

# Loop through all files in the current directory
for file in *; do
  # Check if the file is not a directory and is not already a zip file
  if [ ! -d "$file" ] && [[ "$file" != *.zip ]]; then
      # Create a zip file with the same name as the original file with .zip extension
      info "Encrypting $file ..."
      zip --encrypt --password "$password" "$file.zip" "$file"
  fi
done
info done
