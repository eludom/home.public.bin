#!/bin/bash
# Ask for password.   For use in org-babel scripts, e.g.
#
# #+begin_src bash :env SUDO_ASKPASS="~/bin/askpass.sh"
#   sudo -A mount whoami
# #+end_src
#
zenity --password --title="Password required"
