#!/usr/bin/env bash
# From https://help.sonatype.com/iqserver/installing/running-iq-server-as-a-service

# The following comment lines are used by the init setup script like the
# chkconfig command for RedHat based distributions. Change as
# appropriate for your installation.

### BEGIN INIT INFO
# Provides:          nexus-iq-server
# Required-Start:    $local_fs $remote_fs $network $time $named
# Required-Stop:     $local_fs $remote_fs $network $time $named
# Default-Start:     3 5
# Default-Stop:      0 1 2 6
# Short-Description: nexus-iq-server service
# Description:       Start the nexus-iq-server service
### END INIT INFO

NEXUS_IQ_SERVER_HOME=/opt/sonatype/nexus-iq-server
NEXUS_IQ_SONATYPEWORK=/opt/sonatype/sonatype-work/clm-server
# The user ID which should be used to run the IQ Server
# # IMPORTANT - Make sure that the user has the required privileges to write into the IQ Server work directory.
RUN_AS_USER="${_NXIQ_USER:-"sonatype"}"
_SUDO="sudo -u ${RUN_AS_USER}"
[ "${RUN_AS_USER}" == "${USER}" ] && _SUDO=""

_JAVA="java"
[ -n "${JAVA_HOME}" ] && _JAVA="${JAVA_HOME%/}/bin/java"

_XMX="${_NXIQ_HEAPSIZE:-"2G"}"
JAVA_OPTIONS="-XX:ActiveProcessorCount=2 -Xms${_XMX} -Xmx${_XMX} -XX:+UnlockDiagnosticVMOptions -XX:+LogVMOutput -XX:LogFile=${NEXUS_IQ_SONATYPEWORK}/log/jvm.log"
# GC log related options are different by Java version.
if ${_JAVA} -XX:+PrintFlagsFinal -version 2>/dev/null | grep -q PrintClassHistogramBeforeFullGC; then
    # probably java 8
    JAVA_OPTIONS="${JAVA_OPTIONS} -XX:+UseG1GC -verbose:gc -XX:+PrintGC -XX:+PrintGCDetails -XX:+PrintGCDateStamps -Xloggc:${NEXUS_IQ_SONATYPEWORK}/log/gc.log -XX:+UseGCLogFileRotation -XX:NumberOfGCLogFiles=10 -XX:GCLogFileSize=1024k -XX:+PrintClassHistogramBeforeFullGC -XX:+TraceClassLoading -XX:+TraceClassUnloading"
    JAVA_OPTIONS="${JAVA_OPTIONS} -Dcom.sun.management.jmxremote -Dcom.sun.management.jmxremote.port=6786 -Dcom.sun.management.jmxremote.local.only=false -Dcom.sun.management.jmxremote.authenticate=false -Dcom.sun.management.jmxremote.ssl=false"
else
    # default, expecting java 11
    JAVA_OPTIONS="${JAVA_OPTIONS} -Xlog:gc*:file=${NEXUS_IQ_SONATYPEWORK}/log/gc.log:time,uptime:filecount=10,filesize=1024k"
fi
# _JAVA_OPTIONS should be appended in the last to overwrite
[ -n "${_JAVA_OPTIONS}" ] && JAVA_OPTIONS="${JAVA_OPTIONS} ${_JAVA_OPTIONS}"

do_start()
{
    cd ${NEXUS_IQ_SONATYPEWORK}
    # Original uses su -m which can inherits almost all env of current user (eg: root), not sure if it was intentional
    ${_SUDO} ${_JAVA} ${JAVA_OPTIONS} -jar ${NEXUS_IQ_SERVER_HOME%/}/nexus-iq-server-*.jar server ${NEXUS_IQ_SERVER_HOME%/}/config.yml &> /tmp/nexus_iq_server.out &
    echo "Started nexus-iq-server"
}

do_console()
{
    cd ${NEXUS_IQ_SONATYPEWORK}
    ${_SUDO} ${_JAVA} ${JAVA_OPTIONS} -jar ${NEXUS_IQ_SERVER_HOME%/}/nexus-iq-server-*.jar server ${NEXUS_IQ_SERVER_HOME%/}/config.yml
}

do_stop()
{
    local pid=$(ps -o pid,command -u ${RUN_AS_USER} -U ${RUN_AS_USER} | grep -m1 -P '\bjava .+/nexus-iq-server.*jar server ' | awk '{print $1}')
    if [ -n "${pid}" ]; then
        kill $pid || return $?
        echo "Killed nexus-iq-server - PID $pid"
    fi
}

do_usage()
{
    echo "Usage: nexus-iq-server [console|start|stop]"
}

case $1 in
    console)
        do_console
        ;;
    start)
        do_start
        ;;
    stop)
        do_stop
        ;;
    *)
        do_usage
        ;;
esac