#! /bin/bash
#  list most frequently run commands

cat ~/.bash_history |  awk '{print $1 }' | sort | uniq -c | sort -rn 
