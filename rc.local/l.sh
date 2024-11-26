#! /bin/bash
#   logging funciton for one lineers
#
#  Usage: l ARGS

# set LOGTO if logs go to non-defaut
# this is for installing/migratihng to Manjaro c.a. 2022-10-17


# include my helper funcs or define simple versions inline
if [ -f $HOME/lib/bash/bashutils.sh ]; then
    source $HOME/lib/bash/bashutils.sh
else
    function info()  { echo `date +%c` \: info: "$@" 1>&2; }
    function warn()  { echo `date +%c` \: warning: "$@" 1>&2; }
    function error() { echo `date +%c` \: error: "$@" 1>&2; }
    function debug() { [[ -v DEBUG ]] && echo `date +%c` \: debug: "$@" 1>&2 || true ; }
    function die()   { echo `date +%c` \: fatal: "$@" 1>&2 && exit 1; }
fi

export LOGTO_FILE="install.log"

LOGDIR="${HOME}/var/log"
mkdir -p $LOGDIR

if [  "${LOGTO_FILE}" == "" ] ; then
    export LOGTO="${LOGDIR}/logto.log"
else
    export LOGTO="${LOGDIR}/${LOGTO_FILE}"
fi
# For good measure "sudo chattr +a $LOGTO"

function l() (
    NOW=`date +%Y-%m-%d:%H:%M:%S`

    if  [  $# == 0 ]; then
        warn Nothing to log
        return 1
    fi

    echo ${NOW}: $* >> $LOGTO
    )

function ltail() (
    # tail the logfile

    info $LOGTO

    tail $* $LOGTO
    )
