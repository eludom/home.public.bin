#!/usr/bin/env python
# -*- coding: utf-8 -*-

# """
# Hardlink new .pdf and org files into ~/Documents/notes

# You can use the following Bash script to find all =.pdf= and =.org=
# files modified in the last 2 days under your =$HOME= directory and
# hard link them to =~/Documents/notes= if no file with the same inode
# number already exists.
# """

# __author__ = 'George Jones'
# __maintainer__ = 'George Jones'
# __email__ = 'gmj@pobox.com'
# __version__ = '0.0.1'

# import os
# import time
# import stat
# import errno
# from pathlib import Path

# MTIME_DAYS = 1
# MAXFILES = 100

# SOURCE_DIR = Path.home()
# DEST_DIR = Path.home() / "Documents" / "notes"

# # Create destination directory if it doesn't exist
# DEST_DIR.mkdir(parents=True, exist_ok=True)

# # Calculate the cutoff time for modification
# cutoff_time = time.time() - (MTIME_DAYS * 86400)

# # Function to get the inode of a file
# def get_inode(file_path):
#     inode = -1
#     try:
#         inode = os.stat(file_path).st_ino
#     except:
#         print(f'Error trying to stat {file_path}')
        
#     return inode

# # Process files
# linked_files_count = 0
# for file_path in Path(SOURCE_DIR).rglob('*'):
#     # print("Checking: %s", file_path)
#     # if not file_path.name.endswith("sig.pdf"):
#         # continue
#     if file_path.is_symlink():  # Skip symbolic links
#         continue
#     if linked_files_count >= MAXFILES:
#         break
#     if file_path.suffix in ['.pdf', '.org'] and file_path.stat().st_mtime >= cutoff_time:
#         # print("trying: ", file_path)
#         # try:
#             inode = get_inode(file_path)
#             # print("  inode is ", inode)

#             if inode == -1:
#                 continue
#             # Check if a file with the same inode already exists in the destination
    
#             file_exists = False
#             # print("  file_exists before loop is is ", file_exists)
#             for dest_file in DEST_DIR.iterdir():
#                 if get_inode(dest_file) == inode:
#                     file_exists = True
#                     # print("Exists: ", file_path, dest_file, inode)
#                     # print(  "break")
#                     break
#                 # else:
#                 #     print("  Not found", file_path,dest_file,inode)
#             # print("Loop is done")
#             # print("  file_exists after loop is is ", file_exists)   
                   
#             if not file_exists:
#                 # Create the hardlink
#                 os.link(file_path, DEST_DIR / file_path.name)
#                 print(f'Linked: {file_path} -> {DEST_DIR / file_path.name}')
#                 linked_files_count += 1

#         # except OSError as e:
#         #     if e.errno != errno.ENOENT:  # Skip if the file does not exist anymore
#         #         print(f'Error linking {file_path}: {e}')


# # Add a "--dryrun|-d" flag to only print files that would be linked


# Here's an improved version of your script adding the `--dryrun` flag functionality and cleaning up unused comments:

# ```python
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

MTIME_DAYS = 1
MAXFILES = 100

SOURCE_DIR = Path.home()
DEST_DIR = Path.home() / "Documents" / "notes"

# Create destination directory if it doesn't exist
DEST_DIR.mkdir(parents=True, exist_ok=True)

# Function to get the inode of a file
def get_inode(file_path):
    try:
        return os.stat(file_path).st_ino
    except Exception:
        print(f'Error trying to stat {file_path}')
        return -1

def main(dry_run):
    # Calculate the cutoff time for modification
    cutoff_time = time.time() - (MTIME_DAYS * 86400)

    linked_files_count = 0
    for file_path in Path(SOURCE_DIR).rglob('*'):
        if file_path.is_symlink() or linked_files_count >= MAXFILES:
            continue
        if file_path.suffix in ['.pdf', '.org'] and file_path.stat().st_mtime >= cutoff_time:
            inode = get_inode(file_path)

            if inode == -1:
                continue
            
            if not any(get_inode(dest_file) == inode for dest_file in DEST_DIR.iterdir()):
                target_file = DEST_DIR / file_path.name
                if dry_run:
                    print(f'DRY RUN: Would link: {file_path} -> {target_file}')
                else:
                    os.link(file_path, target_file)
                    print(f'Linked: {file_path} -> {target_file}')
                    linked_files_count += 1

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description='Hardlink .pdf and .org files modified recently.')
    parser.add_argument('--dryrun', '-d', action='store_true', help='Perform a dry run without linking files')
    args = parser.parse_args()
    main(args.dryrun)
# ```

# This version introduces command-line argument parsing to allow for a dry run mode, which simply prints what would be linked instead of creating actual hard links.
