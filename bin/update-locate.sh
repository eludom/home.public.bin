#!/bin/bash

# ==============================================================================
# AUTHOR:       George Jones
# DATE:         2026-10-28
# LICENSE:      GNU GPLv3 (https://gnu.org)
# DEVELOPED BY: Gemini (Google DeepMind AI Model)
#
# CONTEXT & ENVIRONMENT:
# Developed for Manjaro Linux (and other modern Linux distributions using the 
# plocate/mlocate engines).
#
# WHY THIS SCRIPT IS NECESSARY:
# System-wide 'updatedb' runs as root and obeys /etc/updatedb.conf, which often
# blocks /home scanning due to security, network, or encryption pruning rules.
# Additionally, normal 'locate' hides 'chmod 700' files from regular users.
#
# HOW THIS DIFFERS FROM A REGULAR SYSTEM UPDATE:
# 1. Non-Root: Runs completely in user space without requiring 'sudo'.
# 2. Complete Pruning Bypass (-n, -e, -f): Disables all global skip lists.
# 3. Visibility Override (--require-visibility no): Catalogs files even if 700.
# 4. Target Isolation (-U): Restricts traversal purely to the user's home folder.
#
# SUGGESTED ALIAS (Add to ~/.bashrc or ~/.zshrc):
#   alias mylocate="locate -d \$HOME/.local/share/locate.db"
#
# AUTOMATION / SUGGESTED CRON (Run 'crontab -e' as your normal user):
#   0 2 * * * /bin/bash /home/YOUR_USERNAME/bin/update-locate.sh
# ==============================================================================

# --- PARAMETERS ---
LOG_DIR="$HOME/var/log"
LOG_FILE="update-locate.log"
DB_DIR="$HOME/.local/share"
DB_FILE="locate.db"

# Combine paths
FULL_LOG_PATH="$LOG_DIR/$LOG_FILE"
FULL_DB_PATH="$DB_DIR/$DB_FILE"

# --- USAGE STATEMENT ---
usage() {
    echo "Usage: $(basename "$0") [--help]"
    echo "Runs a custom, unrestricted file indexing sweep of your home directory."
    echo "Outputs logs to: $FULL_LOG_PATH"
    echo "Updates database: $FULL_DB_PATH"
    exit 0
}

# Handle basic usage help flag
if [[ "$1" == "-h" || "$1" == "--help" ]]; then
    usage
fi

# --- EXECUTION ---
# Ensure directories exist
mkdir -p "$LOG_DIR"
mkdir -p "$DB_DIR"

# Log the starting timestamp
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Starting personal updatedb..." >> "$FULL_LOG_PATH" 2>&1

# Run the customized database indexing process
updatedb \
  -o "$FULL_DB_PATH" \
  --require-visibility no \
  -n "" -e "" -f "" \
  -U "$HOME" >> "$FULL_LOG_PATH" 2>&1

# Log the completion timestamp
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Database sync complete." >> "$FULL_LOG_PATH" 2>&1
