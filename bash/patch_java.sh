#!/usr/bin/env bash
# curl -o /var/tmp/share/patch_java.sh https://raw.githubusercontent.com/hajimeo/samples/master/bash/patch_java.sh
# bash /var/tmp/share/patch_java.sh <port> <ClassName> </some/path/to/filename.jar>
#
# TODO: currently the script filename needs to be "ClassName.java" (case sensitive)
#

function f_javaenvs() {
    local _port="${1}"
    local _p=`lsof -ti:${_port} -s TCP:LISTEN`
    if [ -z "${_p}" ]; then
        echo "Nothing running on port ${_port}"
        return 11
    fi
    local _user="`stat -c '%U' /proc/${_p}`"
    local _dir="$(dirname `readlink /proc/${_p}/exe` 2>/dev/null)"
    export JAVA_HOME="$(dirname $_dir)"
    if [ -z "$CLASSPATH" ]; then
        export CLASSPATH=".:`sudo -u ${_user} $JAVA_HOME/bin/jcmd ${_p} VM.system_properties | sed -nr 's/^java.class.path=(.+$)/\1/p' | sed 's/[\]:/:/g'`"
    else
        export CLASSPATH="${CLASSPATH%:}:`sudo -u ${_user} $JAVA_HOME/bin/jcmd ${_p} VM.system_properties | sed -nr 's/^java.class.path=(.+$)/\1/p' | sed 's/[\]:/:/g'`"
    fi
}

function f_jargrep() {
    local _class="${1}"
    local _path="${2:-.}"
    local _cmd="jar -tf"
    which jar &>/dev/null || _cmd="less"
    find -L ${_path%/} -type f -name '*.jar' -print0 | xargs -0 -n1 -I {} bash -c "${_cmd} {} | grep -w '${_class}' >&2 && echo '^ Jar: {}'"
}

function f_update_jar() {
    local _jar_filepath="$1"
    local _compiled_dir_or_class_name="$2"

    if [ ! -d "$JAVA_HOME" ]; then
        echo "JAVA_HOME is not set"
        return 1
    fi

    local _jar_filename="$(basename ${_jar_filepath})"
    if [ ! -s "${_jar_filename}.orig" ]; then
        cp -p ${_jar_filepath} ${_jar_filename}.orig || return $?
    fi

    if [ ! -d "${_compiled_dir_or_class_name}" ]; then
        local _class_fullpath="`find . -name "${_compiled_dir_or_class_name}.class" -print`"
        _compiled_dir_or_class_name="`dirname ${_class_fullpath}`"
    fi
    echo "Updating ${_jar_filepath} ..."
    $JAVA_HOME/bin/jar -uvf ${_jar_filepath} ${_compiled_dir_or_class_name%/}/*.class || return $?
    cp -f ${_jar_filepath} ${_jar_filename}.patched
    return 0
}

### Main ###############################
if [ "$0" = "$BASH_SOURCE" ]; then
    _PORT="$1"
    _CLASS_NAME="$2"
    _JAR_FILEPATH="$3"

    if [ -z "$_PORT" ]; then
        echo "At this moment, a port number (1st arg) is required to use this script (used to find a PID)."
        exit 1
    fi
    f_javaenvs "$_PORT" || exit $?

    if [ ! -s "${_CLASS_NAME}.java" ]; then
        echo "At this moment, a java class name (3rd arg) is required to patch a java class."
        exit 1
    fi
    if [ ! -e "${_JAR_FILEPATH}" ]; then
        echo "A jar path (3rd arg) is required to patch a java class."
        exit 1
    fi

    if [ -d "${_JAR_FILEPATH}" ]; then
        f_jargrep "${_CLASS_NAME}.class" "${_JAR_FILEPATH}"
        echo "Please pick a jar file from above, and re-run the script."
        exit 0
    fi

    # to avoid Java heap space error (default seems to be set to 256m)
    JAVA_OPTS=-Xmx1024m javac "${_CLASS_NAME}".java || exit $?
    f_update_jar "${_JAR_FILEPATH}" "${_CLASS_NAME}" || exit $?
    echo "Completed. Please restart the process (current PID=`lsof -ti:${_PORT} -s TCP:LISTEN`)."
fi