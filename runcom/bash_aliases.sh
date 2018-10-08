### Simple/generic alias commands (some need pip though) ###############################################################
# cd to the last modified dir
alias cdl='cd "`ls -dtr ./*/ | tail -n 1`"'
alias urldecode='python -c "import sys, urllib as ul; print ul.unquote_plus(sys.argv[1])"'
alias urlencode='python -c "import sys, urllib as ul; print ul.quote_plus(sys.argv[1])"'
alias utc2int='python -c "import sys,time,dateutil.parser;print int(time.mktime(dateutil.parser.parse(sys.argv[1]).timetuple()))"'  # doesn't work with yy/mm/dd (2 digits year)
alias int2utc='python -c "import sys,time;print time.asctime(time.gmtime(int(sys.argv[1])))+\" UTC\""'
# Start python interactive after loading json object in 'pdf' (pandas dataframe)
#alias pandas='python -i <(echo "import sys,json;import pandas as pd;f=open(sys.argv[1]);jd=json.load(f);pdf=pd.DataFrame(jd);")'
alias pandas='python -i <(echo "import sys,json;import pandas as pd;pdf=pd.read_json(sys.argv[1]);")'
alias rmcomma='sed "s/,$//g; s/^\[//g; s/\]$//g"'
alias ht='for _f in `ls -1tr`; do echo "$_f"; head -n1 $_f | sed "s/^/  /"; tail -n1 $_f | sed "s/^/  /"; done'


## Non generic (OS/host/app specific) alias commands ###################################################################
# Load/source my log searching utility functions
#mkdir -p ~/IdeaProjects/samples/bash; curl -o ~/IdeaProjects/samples/bash/log_search.sh https://raw.githubusercontent.com/hajimeo/samples/master/bash/log_search.sh
alias logS="source ~/IdeaProjects/samples/bash/log_search.sh"
alias xmldiff="python ~/IdeaProjects/samples/python/xml_parser.py"

# Java / jar related
alias mb='java -jar ~/Applications/metabase.jar'    # port is 3000
alias vnc='nohup java -jar ~/Applications/tightvnc-jviewer.jar &>/tmp/tightvnc-jviewer.out &'

# Python simple http server from the specific dir
# To setup: asDocSync <server ip>
alias webs='cd ~/Public/atscale_latest/ && nohup python -m SimpleHTTPServer 38081 &>/tmp/python_simplehttpserver.out & nohup python ~/IdeaProjects/samples/python/SympleWebServer.py &>/tmp/python_simplewebserver.out &'
# List and grep some specific files from s3. NOTE: https:// requires s3-us-west-1.amazonaws.com

# Work specific aliases
alias asS3='s3cmd ls s3://files.atscale.com/installer/package/ | grep -E "atscale-[56789].+latest-el6\.x86_64\.tar\.gz$"'    # TODO: public-repo-1.hortonworks.com private-repo-1.hortonworks.com
alias asPupInst='scp -C ~/IdeaProjects/samples/atscale/install_atscale.sh root@192.168.6.162:/var/tmp/share/atscale/ & scp -C ~/IdeaProjects/samples/atscale/install_atscale.sh root@192.168.0.31:/var/tmp/share/atscale/ & scp -C ~/IdeaProjects/samples/atscale/install_atscale.sh root@192.168.6.160:/var/tmp/share/atscale/'


### Functions (some command syntax does not work with alias eg: sudo) ##################################################
# Start Jupyter Notebook with Aggregation template (and backup-ing)
function jp() {
    local _id="${1}"
    local _backup_dir="${2-$HOME/backup/jupyter-notebook}"
    local _template="${3-Aggregation.ipynb}"
    local _sleep="${4:-180}"
    local _port="${5:-8889}"

    if [ -n "${_backup_dir}" ] && [ ! -d "${_backup_dir}" ]; then
        mkdir -p "${_backup_dir}" || return 11
    fi

    [ -n "${_id}" ] && _id="_${_id}"

    if [ -d "${_backup_dir}" ]; then
        # http://ipython.org/ipython-doc/1/config/overview.html#startup-files
        if [ ! -f ~/.ipython/profile_default/startup/${_template%.*}.py ] && [ -s ${_backup_dir%/}/${_template%.*}.py ]; then
            cp ${_backup_dir%/}/${_template%.*}.py ~/.ipython/profile_default/startup/${_template%.*}.py
        fi

        [ -s ./${_template%.*}${_id}.ipynb ] && [ -d ~/.Trash ] && mv ./${_template%.*}${_id}.ipynb ~/.Trash/

        [ -s "${_backup_dir%/}/${_template}" ] && cp -f "${_backup_dir%/}/${_template}" ./${_template%.*}${_id}.ipynb
        while true; do
            sleep ${_sleep}
            if [  "`ls -1 ./*.ipynb 2>/dev/null | wc -l`" -gt 0 ]; then
                rsync -a --exclude="Untitled.ipynb" ./*.ipynb "${_backup_dir%/}/" || break
                # TODO: if no ipynb file to backup, should break?
            fi
            if ! lsof -ti:${_port} &>/dev/null; then
                if [ -d ~/.Trash ]; then
                    mv -f ${_template%.*}${_id}.ipynb ~/.Trash/
                else
                    mv -f ${_template%.*}${_id}.ipynb /tmp/
                fi
                break
            fi
        done &
    fi

    jupyter lab --ip='localhost' --port=${_port} &
}

# Mac only: Start Google Chrome in incognito with proxy
function chromep() {
    local _host_port="${1:-"192.168.6.162:28081"}"
    local _url=${2}

    local _host="${_host_port}"
    local _port="28081"
    if [[ "${_host_port}" =~ ^([0-9.]+):([0-9]+)$ ]]; then
        _host="${BASH_REMATCH[1]}"
        _port="${BASH_REMATCH[2]}"
    fi
        local _port=${3:-28081}
    [ ! -d $HOME/.chromep/${_host}_${_port} ] && mkdir -p $HOME/.chromep/${_host}_${_port}
    if [ -n "${_url}" ]; then
        if [[ ! "${_url}" =~ ^http ]]; then
            _url="--app=http://${_url}"
        else
            _url="--app=${_url}"
        fi
    fi
    #nohup "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" --user-data-dir=$HOME/.chromep/${_host}_${_port} --proxy-server="socks5://${_host}:${_port}" ${_url} &>/tmp/chrome.out &
    open -na "Google Chrome" --args --user-data-dir=$HOME/.chromep/${_host}_${_port} --proxy-server=socks5://${_host}:${_port} ${_url}
    echo 'open -na "Google Chrome" --args --user-data-dir=$(mktemp -d) --proxy-server=socks5://'${_host}':'${_port}' '${_url}
}

# List files against hostname 'asftp'. NOTE: the hostname 'asftp' is specified in .ssh_config
function asftpl() {
    local _name="${1}"
    local _n="${2:-20}"
    if [[ "$1" =~ ^[0-9]+$ ]]; then
        _n=$1
        _name="${2}"
    fi
    #ssh -q asftp -t 'cd /home/ubuntu/upload && find . -type f -mtime -2 -size +10240k -name "'${_name}'" -ls | sort -k9,10 | tail -n'${_n}
    ssh -q asftp -t 'cd /home/ubuntu/upload && ls -lhtr '${_name}'| tail -n'${_n}';date'
}
# Download files from hostname 'asftp'. NOTE: the hostname 'asftp' is specified in .ssh_config
function asftpd() {
    [ -z "$1" ] && ( asftpl; return 1 )
    for _a in "$@"; do
        local _ext="${_a##*.}"
        local _rsync_opts="-Phz"
        [[ "${_ext}" =~ ^gz|zip|tgz$ ]] && _rsync_opts="-Ph"
        rsync ${_rsync_opts} asftp:"/home/ubuntu/upload/$_a" ./
    done
}
function asDocSync() {
    local _server="$1"
    local _loginas="${2:-root}"
    rsync -Phrz ${_loginas}@${_server}:/usr/local/atscale/apps/modeler/assets/modeler/public/docs/* ~/Public/atscale_latest/
    cd ~/Public/atscale_latest/ && patch -p0 -b < ~/IdeaProjects/samples/misc/doc_index.patch
}

# Grep against jar file to find a class ($1)
function jargrep() {
    local _cmd="jar -tf"
    which jar &>/dev/null || _cmd="less"
    find -L ${2:-./} -type f -name '*.jar' -print0 | xargs -0 -n1 -I {} bash -c ''${_cmd}' {} | grep -wi '$1' && echo {}'
}
function javacp() {
    local _pid="$1"
    local _user="`stat -c '%U' /proc/${_pid}`" || return $?
    local _cmd_dir="$(dirname `readlink /proc/${_pid}/exe`)" || return $?
    sudo -u ${_user} ${_cmd_dir}/jcmd ${_pid} VM.system_properties | grep '^java.class.path=' | sed 's/\\:/:/g' | cut -d"=" -f 2
}
# Grep file(s) with \d\d\d\d-\d\d-\d\d.\d\d:\d (upto 10 mins) and pass to bar_chart
function bar() {
    ggrep -oP "${2:-^\d\d\d\d-\d\d-\d\d.\d\d:\d}" ${1-./*} | bar_chart.py
}
# Add route to dockerhost to access containers directly
function r2dh() {
    local _3rd="${1:-100}"  # 3rd decimal in network address
    local _dh="${2:-192.168.0.31}"  # docker host IP
    if [ "Darwin" = "`uname`" ]; then
        sudo route delete -net 172.17.${_3rd}.0/24 &>/dev/null;sudo route add -net 172.17.${_3rd}.0/24 ${_dh}
        sudo route delete -net 172.18.0.0/24 &>/dev/null;sudo route add -net 172.18.0.0/24 ${_dh}
    elif [ "Linux" = "`uname`" ]; then
        sudo ip route del 172.17.${_3rd}.0/24 &>/dev/null;sudo route add -net 172.17.${_3rd}.0/24 gw ${_dh} ens3
    else    # Assuming windows (cygwin)
        route delete 172.17.${_3rd}.0 &>/dev/null;route add 172.17.${_3rd}.0 mask 255.255.255.0 ${_dh};
    fi
}
function sshs() {
    local _user_at_host="$1"
    local _session_name="${2}"
    local _cmd="screen -r || screen -ls"
    [ -n "${_session_name}" ] && _cmd="screen -x ${_session_name} || screen -S ${_session_name}"
    ssh ${_user_at_host} -t ${_cmd}
}
# backup commands
function backupC() {
    local _src="${1:-"$HOME/Documents/cases"}"
    local _dst="${2:-"hosako@192.168.0.11:/cygdrive/h/hajime/cases"}"
    [ ! -d "${_src}" ] && return 11
    [ ! -d "$HOME/.Trash" ] && return 12
    local _size="10000k"
    # Delete files larger than _size (10MB) and older than one year
    find ${_src%/} -type f -mtime +365 -size +${_size} -print0 | xargs -0 -t -n1 -I {} mv {} $HOME/.Trash/ &
    # Delete files larger than 200MB and older than 90 days
    find ${_src%/} -type f -mtime +90 -size +200000k -print0 | xargs -0 -t -n1 -I {} mv {} $HOME/.Trash/ &
    # Synch all files smaller than _size (10MB)
    rsync -Pvaz --max-size=${_size} --modify-window=1 ${_src%/}/* ${_dst%/}/
    wait
}