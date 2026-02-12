#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
Hardlink new .pdf and .org files into ~/Documents/notes, 
modified in the last few days, skipping duplicates.
"""


import os
import time
import argparse
from pathlib import Path

# Set default values for mtime days and max files
DEFAULT_MTIME_DAYS = 4
DEFAULT_MAXFILES = 60

SOURCE_DIR = Path.home()
DEST_DIR = Path.home() / "Documents" / "notes"

# Create destination directory if it doesn't exist
DEST_DIR.mkdir(parents=True, exist_ok=True)

# Default directories to ignore
DEFAULT_IGNORE_DIRS = [Path.home() / "orgfiles", Path.home() / "tmp", Path.home() / "Downloads", Path.home() / ".local", Path.home() / "notes-recover", Path.home() / "notes-recover-raw", Path.home() / "stow/home.private.notes/notes"]

def get_inode(file_path):

    try:
        return os.stat(file_path).st_ino
    except Exception:
        return -1

def main(test_run, ignore_dirs, mtime_days, max_files):
    cutoff_time = time.time() - (mtime_days * 86400)
    linked_files_count = 0
    ignore_dirs = [Path(dir) for dir in ignore_dirs]
    ignored_dirs_set = set()


    for file_path in Path(SOURCE_DIR).rglob('*'):

        if ".#" in str(file_path):
            continue
        
        if file_path.is_symlink() or not file_path.is_file() or linked_files_count >= max_files:
            continue

        # Check each ignore directory and handle accordingly
        is_ignored = False
        for ignore_dir in ignore_dirs:
            if file_path.is_relative_to(ignore_dir):
                if ignore_dir not in ignored_dirs_set:
                    print(f'Ignoring directory: {ignore_dir}')
                    ignored_dirs_set.add(ignore_dir)
                is_ignored = True
                break  # Exit once the file is confirmed to be ignored

        if is_ignored:
            continue

        if file_path.suffix in ['.pdf', '.org', '.ods', '.odt','.docx', '.xls','.xlsx'] and file_path.stat().st_mtime >= cutoff_time:
            inode = get_inode(file_path)

            if inode == -1:
                continue
            
            if not any(get_inode(dest_file) == inode for dest_file in DEST_DIR.iterdir()):
                target_file = DEST_DIR / file_path.name

                # Check if target file already exists, if so, add timestamp
                if target_file.exists():
                    timestamp = time.strftime("%Y%m%dT%H%M%S", time.gmtime())
                    target_file = DEST_DIR / f"{timestamp}--{file_path.name}"
                    print("Added timestamp to ", target_file)

                if test_run:
                    print(f'DRY RUN: Would link: {file_path} -> {target_file}')
                else:
                    print(f'Linking: {file_path} -> {target_file}')

                    try:
                        os.link(file_path, target_file)
                    except Exception:
                        print(f'Failed to link {file_path} -> {target_file}')
                    linked_files_count += 1

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description='Hardlink .pdf and .org files modified recently.')
    parser.add_argument('--test_run', '-t', action='store_true', help='Perform a dry run without linking files')
    parser.add_argument('--ignore', '-i', nargs='*', default=DEFAULT_IGNORE_DIRS, help='Directories to ignore')
    parser.add_argument('--days', '-d', type=int, default=DEFAULT_MTIME_DAYS, help='Number of days to check for modified files (default: 3)')
    parser.add_argument('--maxfiles', '-m', type=int, default=DEFAULT_MAXFILES, help='Maximum number of files to link (default: 60)')
    args = parser.parse_args()
    main(args.test_run, args.ignore, args.days, args.maxfiles)

