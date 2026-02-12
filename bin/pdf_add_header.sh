#!/bin/bash 
# This script adds a header to PDF files consisting of filename, page number and current date.
#
# Usage: pdf_add_header.sh INPUT.pdf OUTPUT.pdf

# This is bash; be safe.
set -e
set -u

# Check if the correct number of arguments is provided
if [ $# -ne 2 ]; then
    echo "Usage: $0 <input> <output>"
    exit 1
fi

# Input filename
input_file="$1"

# Output filenames
temp_file="temp1.pdf"
output_file="$2"

# Add space at the top of the PDF
cpdf -shift "0pt 26pt" "$input_file" -o "$temp_file"

# Add header with filename, page, and date
cpdf -topleft 10 -font Courier -add-text "$1 Page %Page Printed %Y-%m-%d" "$temp_file" -o "$output_file"

# Clean up temporary file
rm "$temp_file"

echo "Processed $input_file and created $output_file"
#+end_src

