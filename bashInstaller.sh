#!/bin/bash
# chkconfig: 345 99 01
# description: some startup script

################################################################################
##
## SCRIPT: bashInstaller.sh
##
## This script
##  - is designed to orchestrate the installation of multiple software components
##  - must be executed as root (or under sudo)
##
## Using the install option, the script installs itself as a service
##  - This is to allow reboots during the installation
##  - After installation as a service, the service is started and the initial script execution exits
##
## The script reads an INI_FILE section by section
##  - each section is checkpointed *prior* to execution of the section's install script
##  - in the event of reboot, checkpointed sections will be skipped
##
## The INI_FILE should have multiple sections of the following format
##
##     [section_name]
##     zipFile=<mandatory http(s) url to zip file containing all install files>
##     scriptFile=<mandatory full path to install script within the zipFile structure>
##     iniFile=<optionally null http(s) url to ini file to drive the installation>
##
## e.g.
##
##     [sw1]
##     zipFile=http://localhost/sw1.zip
##     scriptFile=sw1/bin/configure_sw1.sh
##     iniFile=
##
## If an install script fails, it should return a non zero return code
## On receipt of a non zero return code, processing of this script will halt
##
################################################################################
##
## Version    Date      Author         Description of change
## =======    ========  ==========     =====================
## 0.1        8/Aug/16  atu045         initial creation
## 0.2        8/Aug/16  atu045         Checkpointing
##
################################################################################

g_prog=bashInstaller
RETVAL=0

######################################################
## defined script variables
######################################################
STAGE_DIR=/tmp/$g_prog/stage
LOG_DIR=/var/log/$g_prog
ETC_DIR=/etc/$g_prog
CHECKPOINT_DIR=/var/run/$g_prog
CHECKPOINT_FILE=$CHECKPOINT_DIR/${g_prog}.ckp
INI_FILE=$ETC_DIR/`hostname`.ini
LOG_FILE=$LOG_DIR/${prog}.log.$(date +%Y%m%d_%H%M%S_%N)


######################################################
## log()
##
##   parameter 1 - text to log
##
##   1. write parameter #1 to current logfile
##
######################################################
function log ()
{
    if [[ -e $LOG_DIR ]]; then
        echo "$(date +%Y/%m/%d_%H:%M:%S.%N) $1" >> $LOG_FILE
    fi
}

######################################################
## fatalError()
##
##   parameter 1 - text to log
##
##   1.  log a fatal error and exit
##
######################################################
function fatalError ()
{
    MSG=$1
    log "FATAL: $MSG"
    echo "ERROR: $MSG"
    exit -1
}

######################################################
## isSectionCheckpointed()
##
##   parameter 1 - section of the init file
##
##   1. Search the checkpoint file for the section
##   2. Echo the result to stdout: 1 if found, 0 if not found
##   3. Obtain the return value* as follows:
##
##         p_sectionFound=$(isSectionCheckpointed)
##
##  * The above is necessary because Bash does not allow return values from functions
##
######################################################
function isSectionCheckpointed() 
{
    local p_searchSection=$1
    local p_sectionFound=0
    log "isSectionCheckpointed() starting; CHECKPOINT_FILE=$CHECKPOINT_FILE"
    
    if [[ -z p_searchSection ]]; then
        fatal "isSectionCheckpointed() called with null parameter"
    fi
    

    while read CHECKPOINTED_SECTION
    do
        if [[ "$CHECKPOINTED_SECTION" == "$p_searchSection" ]]; then
            p_sectionFound=1
            log "isSectionCheckpointed: Matched $CHECKPOINTED_SECTION to $p_searchSection; already processed"
            break;
        fi
    done < $CHECKPOINT_FILE
    
    log "isSectionCheckpointed() ending"
    echo $p_sectionFound
}

######################################################
## checkpointSection()
##
##   parameter 1 - section of the init file
##
##   1. Add section to the checkpoint file
##
######################################################
function checkpointSection() 
{
    local p_section=$1
    log "checkpointSection() starting; putting SECTION=${p_section} in CHECKPOINT_FILE=$CHECKPOINT_FILE"
    
    if [[ -z p_section ]]; then
        fatal "checkpointSection() called with null parameter"
    fi

    echo ${p_section} >> $CHECKPOINT_FILE
    
    log "checkpointSection() ending"
}


######################################################
## executeSection()
##
##   parameter 1 - section of the init file
##   parameter 2 - url of the zipped install package
##   parameter 3 - script within the zipped install package that should be executed
##
##   1. download the zip (ZIP_URL)
##   2. extract the zip, and
##   3. execute the install script (INSTALL_SCRIPT)
##
######################################################
function executeSection ()
{
    log "executeSection() starting"
    
    local p_section=$1
    local p_zip_url=$2
    local p_installScript=$3
    local p_initFile=$4
    local l_installScriptDir=$(dirname $p_installScript)
    local l_installScriptFile=$(basename $p_installScript)
    local l_zipFile=$(basename $p_zip_url)
    local l_functionName="executeSection"
    local l_retval

    if [ -z "${p_section}" ]; then
        fatalError "${l_functionName} called with null section parameter"
    elif [ -z "$p_zip_url" ]; then
        fatalError "${l_functionName} called with null ZIP_URL parameter for section=${p_section}"
    elif [ -z "$l_zipFile" ]; then
        fatalError "${l_functionName} cannot get basename of ZIP_URL parameter: ${p_zip_url} for p_section=${p_section}"
    elif [ -z "$p_installScript" ]; then
        fatalError "${l_functionName} called with null SCRIPT parameter for section=${p_section}"
    fi
   
    l_retval=$(isSectionCheckpointed $p_section)
    log "executeSection: $l_retval from isSectionCheckpointed"

    if [ $l_retval -eq 0 ]; then
        checkpointSection ${p_section}    
    
        if [ -d $STAGE_DIR/${p_section} ]; then
            fatalError "${l_functionName} target directory already exists for section=${p_section}"
        fi

        if ! mkdir -p $STAGE_DIR/${p_section}; then
            fatalError "${l_functionName} error with mkdir for section=${p_section}"
        fi
        cd $STAGE_DIR/${p_section}

        if ! wget -o $LOG_DIR/wget.${p_section}.log.$$ $p_zip_url; then
            cat $LOG_DIR/wget.${p_section}.log.$$
            fatalError "${l_functionName} error with wget for section=${p_section}"
        fi

        if ! unzip -q $l_zipFile; then
            fatalError "${l_functionName} error with unzip $l_zipFile for section=${p_section}"
        fi

        if ! rm $l_zipFile; then
            log "${l_functionName} error deleting $l_zipFile after extract"
        fi

        if [ ! -e $p_installScript ]; then
            fatalError "${l_functionName} from $PWD error locating install script $p_installScript for section=${p_section}"
        fi
        
        if ! sh $p_installScript $p_initFile; then
            fatalError "${l_functionName} error executing install script for section=${p_section}"
        fi
    fi
    log "executeSection() ending"
    
}

######################################################
## processIniSection
##
##  parameter 1 - the SECTION of the INI_FILE being processed
##
##  1. Read the INI_FILE
##  2. If section matched, store settings as environment variables
##  3. Execute the section, passing variables as parameters
##
######################################################
function processIniSection ()
{
    log "processIniSection() starting"

    if [ -z "$1" ]; then
        fatalError "processIniSection called with null parameter"
    fi

    local p_section=$1
    local l_line
    local l_foundSection

    # For the section found, the code expects the ini file to be the correct bash format and allow export of the whole line to set an environment variable
    while read l_line
    do
        if [[ ${l_line} == \[*] ]]; then
            l_foundSection=${l_line//[\[\]]}

        elif [[ $l_line == *=* ]]; then
            if [[ $l_foundSection == $p_section ]]; then
                if ! export "${l_line}"; then
                    fatalError "processIniSection() cannot export $l_line in iniFile=$INI_FILE section=$p_section"
                fi
            fi
        fi
    done <  $INI_FILE

    if [ -z "$zipFile" ]; then
        fatalError "processIniSection zipFile is null for $p_section"
    elif [ -z "$scriptFile" ]; then
        fatalError "processIniSection scriptFile is null for $p_section"
    fi
    log "processIniSection: Calling \"executeSection $p_section $zipFile $scriptFile $iniFile\""
    executeSection $SECTION $zipFile $scriptFile $iniFile

    log "processIniSection() ending"
}


######################################################
## validateIniSections
##
##   1. Read the INI_FILE through
##   2. Check section headings are unique
##   3. Check assignments are syntactically correct
##
######################################################
function validateIniSections ()
{
    local l_line
    local l_cnt

    while read l_line
    do
        if [[ ${l_line} == \[*] ]]; then
            # strip the square brackets, cool bash feature
            l_cnt=`grep "\[${l_line//[\[\]]}\]" $INI_FILE | wc -l`
            if [[ $l_cnt -gt 0 ]]; then
                 fatalError "validateIniSections(): section $l_line is defined $l_cnt times already"
            fi
        fi
        
        if [[ ${l_line} == *=* ]]; then
            if ! export "${l_line}"; then
                 fatalError "validateIniSections(): invalid syntax for $l_line"
            fi
        fi
    done <  $INI_FILE
}


######################################################
## listIniSections
##
##   1. Read the INI_FILE through
##   2. Echo the section headings to STDOUT
##
######################################################
function listIniSections ()
{
    local l_line

    while read l_line
    do
        if [[ ${l_line} == \[*] ]]; then
            # strip the square brackets, cool bash feature
            echo ${l_line//[\[\]]}
        fi
    done <  $INI_FILE
}

######################################################
## start ()
##
##   Invoked at service start time
##   1. Recreate directories as needed
##
######################################################
function start ()
{
    mkdir -p $STAGE_DIR $LOG_DIR $ETC_DIR

    log "begin processing"
    listIniSections | while read SECTION
    do
        processIniSection $SECTION
    done
    log "successful end :)"

#    RETVAL=$?
#    echo
#    [ $RETVAL = 0 ] && touch /var/lock/subsys/${prog}
#    return $RETVAL
}

######################################################
## deinstall
##
##   1. deinstall service
##   2. remove directories
##
######################################################
function deinstall ()
{
    chkconfig --del $g_prog
    rm -r $ETC_DIR $CHECKPOINT_DIR $LOG_DIR $STAGE_DIR
    rm /etc/init.d/$g_prog
}

######################################################
## install
##
##
##
######################################################
function install ()
{
    log "install() starting"
    local p_thisScript=$1
    local INI_URL=$2

    if [ -z "$p_thisScript" ]; then
        fatalError "install() called with null parameter p_thisScript"
    fi

    if [ -z "$INI_URL" ]; then
        fatalError "install() called with null parameter INI_URL"
    fi

    if [ ! -e $p_thisScript ]; then
        fatalError "install() cannot find this script: $p_thisScript"
    fi

    if ! mkdir -p $STAGE_DIR $LOG_DIR $ETC_DIR $CHECKPOINT_DIR; then
        fatalError "install() cannot make required directories: $STAGE_DIR $LOG_DIR $ETC_DIR $CHECKPOINT_DIR"
    fi

    if ! touch $CHECKPOINT_FILE; then
        fatalError "install() cannot touch $CHECKPOINT_FILE"
    fi

    # get and deploy ini file to /etc/$g_prog
    if ! wget -o $LOG_DIR/wget.INI_URL.log -O $INI_FILE $INI_URL; then
        fatalError "install() error with wget for INI_URL=$INI_URL"
    fi

    # copy this script to /etc/init.d
    if ! cp $p_thisScript /etc/init.d/$g_prog; then
        fatalError "install() cannot copy $p_thisScript to init.d"
    fi

    # place under chkconfig control
    if ! chkconfig --add $g_prog; then
        fatalError "install() cannot place $g_prog under chkconfig control"
    fi

    # enable service
    if ! chkconfig $g_prog on; then
        fatalError "install() cannot enable service"
    fi

    log "install() ending"
}

######################################################
## Main Entry Point
######################################################

log "$g_prog starting"
log "STAGE_DIR=$STAGE_DIR"
log "LOG_DIR=$LOG_DIR"
log "ETC_DIR=$ETC_DIR"
log "CHECKPOINT_DIR=$CHECKPOINT_DIR"
log "CHECKPOINT_FILE=$CHECKPOINT_FILE"
log "INI_FILE=$INI_FILE"
log "LOG_FILE=$LOG_FILE"
echo "$g_prog starting, LOG_FILE=$LOG_FILE"

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
SCR=$(basename "${BASH_SOURCE[0]}")
THIS_SCRIPT=$DIR/$SCR

if [[ $EUID -ne 0 ]]; then
    fatalError "$THIS_SCRIPT must be run as root"
    exit 1
fi

case "$1" in
  deinstall)
        if [[ ! -e $ETC_DIR ]]; then
            fatalError "$g_prog is not installed"
        fi
        deinstall
        ;;
  install)
        INI_URL="$2"
        install $THIS_SCRIPT $INI_URL
        ;;
  install_and_start)
        INI_URL="$2"
        install $THIS_SCRIPT $INI_URL
		start
        ;;
  start)
        if [[ ! -e $ETC_DIR ]]; then
            fatalError "$g_prog is not installed"
        fi
        touch /var/lock/subsys/$g_prog
        start
        ;;
  stop)
        if [[ ! -e $ETC_DIR ]]; then
            fatalError "$g_prog is not installed"
        fi
        rm -f /var/lock/subsys/$g_prog
        stop
        ;;
  *)
        echo $"Usage: $g_prog {install INI_URL|start|stop}"

        exit 1
esac

log "$g_prog ended cleanly"
exit $RETVAL


