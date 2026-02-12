#!/bin/bash
# Check to gpg agent is caching a passprhase

source ~/lib/bash/bashutils.sh
KEY_STRING="${1:-gmj@pobox.com}"

# Find the key ID associated with the string
KEY_ID=$(gpg --list-secret-keys --with-colons | grep -i "$KEY_STRING" | head -n 1 | cut -d: -f6)

if [[ -z "$KEY_ID" ]]; then
    die "No key found for string '$KEY_STRING'."
fi
# Attempt to sign a dummy message with the key to see if the passphrase is cached
echo "This is a test." | gpg --batch --yes --default-key "$KEY_ID" --clearsign >/dev/null 2>&1

# Check the exit status of the gpg command
if [ $? -eq 0 ]; then
    info "The passphrase for key '$KEY_STRING' is cached."
    exit $TRUE
else
    info "The passphrase for key '$KEY_STRING' is not cached or other error occurred."
    exit $FALSE
fi
