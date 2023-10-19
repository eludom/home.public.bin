#! /bin/bash
# Do automatic git-commit to any changes in a diredtory
#
# This is intended to be used with "orglinks.sh" which creates
# hard links for all *.org files under, e.g., $HOME to a
# parcicular directory, e.g. ~/orgfiles
#
# Usage: autocommit DIR

# This is bash, be safe
set -u
set -e

# pull in my error, warning, etc.
source ~/lib/bash/bashutils.sh

# Directory provided as an argument
dir="${1:-$HOME/orgfiles}"

# Check if the provided directory exists
if [ ! -d "$dir" ]; then
  error "Error: Directory '$dir' does not exist."
fi

cd $dir

# make sure it is a git root dir

if [ -d $dir/.git ]; then
    :
else
    info initializing git in $dir
    git init .
fi

# Add all org files
info adding all .org files
git add *.org

# get rid of anytthing that's not an .org file
git clean -f

# Git commit changes if any
if [[ $(git status --porcelain) ]]; then
    # Changes exist, so commit them
    info files changed:
    git ls-files -m
    git commit -am "Autocommit `date`"
    info "Changes committed."
else
    # No changes to commit
    info "No changes to commit."
fi
