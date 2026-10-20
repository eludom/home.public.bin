#!/bin/bash
# Monitor org files for unexpected size shrinkage
# Compares current size against the last 3 git commits

LOG_FILE="$HOME/var/log/org-shrink.log"
ORG_DIR="$HOME/Org"
FILES=(diary.org 2026.org web.org)

mkdir -p "$(dirname "$LOG_FILE")"

cd "$ORG_DIR" || exit 1

shrunk=()
for file in "${FILES[@]}"; do
    [[ -f "$file" ]] || continue

    current_size=$(stat -c%s "$file")

    # Get sizes from last 3 commits
    max_prev_size=0
    while read -r size; do
        [[ "$size" -gt "$max_prev_size" ]] && max_prev_size="$size"
    done < <(git log -3 --format=%H -- "$file" | while read -r commit; do
        git cat-file -s "$commit:$file" 2>/dev/null
    done)

    if [[ "$max_prev_size" -gt 0 && "$current_size" -lt "$max_prev_size" ]]; then
        diff=$((max_prev_size - current_size))
        shrunk+=("$file: -${diff} bytes (was $max_prev_size, now $current_size)")
    fi
done

if [[ ${#shrunk[@]} -gt 0 ]]; then
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    msg=$(printf '%s\n' "${shrunk[@]}")

    # Log to file
    {
        echo "[$timestamp] Files shrunk:"
        printf '  %s\n' "${shrunk[@]}"
    } >> "$LOG_FILE"

    # Persistent notification (timeout 0 = stays until acknowledged)
    notify-send -u critical -t 0 "Org files shrunk" "$msg"

    echo "WARNING: Files shrunk:" >&2
    printf '%s\n' "${shrunk[@]}" >&2
    exit 1
fi
