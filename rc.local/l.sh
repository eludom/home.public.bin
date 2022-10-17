#! /bin/bash
#   logging funciton for one lineers
#
#  Usage: l ARGS

NOW=`date +%Y-%fM-%d:%H:m:s`
LOGDIR="${HOME/var/log}"

if [  "${LOGTO}" == "" ] ; then
    mkdir -p $LOGDIR
    LOGFILE="${LOGDIR}/l.log"
else
    LOGFILE="${$LOGTO}"
fi

if  [  $# == 0 ]; then
    echo Nothing to log
    return 1
fi

echo $* >> $LOGFILE
