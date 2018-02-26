#!/usr/bin/env bash
#
# Based on https://gist.github.com/rajkrrsingh/24ff6f426248276cfa79063967f08213
#
# Download and execute this script:
#   curl -O https://raw.githubusercontent.com/hajimeo/samples/master/bash/hive_dummies.sh
#   bash ./hive_dummies.sh [dbname] [beeline conn str (No -n or -p)]
#

g_LOG_FILE_PATH=""
g_WORK_DIR="./hive_workspace"

function _log() {
    if [ -n "$g_LOG_FILE_PATH" ]; then
        echo -e "[$(date +'%Y-%m-%d %H:%M:%S')] $@" | tee -a $g_LOG_FILE_PATH
    else
        echo -e "[$(date +'%Y-%m-%d %H:%M:%S')] $@" 1>&2
    fi
}

### Main ###############################################################################################################
if [ "$0" = "$BASH_SOURCE" ]; then
    # Process arguments
    _dbname="${1}"
    _beeline_u="${2}"

    [ -z "$_dbname" ] && _dbname="dummies"

    _cmd="hive -hiveconf hive.tez.exec.print.summary=true"
    [ -n "${_beeline_u}" ] && _cmd="beeline --verbose=true --outputformat=tsv2 -u '${_beeline_u}' -n $USER"
    # -hiveconf hive.root.logger=DEBUG,console
    _cmd="${_cmd} -hiveconf hive.tez.exec.print.summary=true"

    # Prepare (create a work dir and remove old csv files)
    [ -d "${g_WORK_DIR%/}" ] || mkdir ${g_WORK_DIR%/}
    rm -f ${g_WORK_DIR%/}/*.csv
    _sql="CREATE DATABASE IF NOT EXISTS ${_dbname};USE ${_dbname};set hive.tez.container.size=1024;set hive.tez.java.opts=-Xmx820m;"

    _log "INFO" "generating dummy csv files..."
    wget -nv -c -t 2 --timeout=10 --waitretry=3 https://raw.githubusercontent.com/hajimeo/samples/master/misc/sample_07.csv -O ${g_WORK_DIR%/}/sample_07.csv
    wget -nv -c -t 2 --timeout=10 --waitretry=3 https://raw.githubusercontent.com/hajimeo/samples/master/misc/sample_08.csv -O ${g_WORK_DIR%/}/sample_08.csv
    wget -nv -c -t 2 --timeout=10 --waitretry=3 https://raw.githubusercontent.com/hajimeo/samples/master/misc/census.csv -O ${g_WORK_DIR%/}/census.csv
    echo '101,Kyle,Admin,50000,A
    102,Xander,Admin,50000,B
    103,Jerome,Sales,60000,A
    104,Upton,Admin,50000,C
    105,Ferris,Admin,50000,C
    106,Stewart,Tech,12000,A
    107,Chase,Tech,12000,B
    108,Malik,Engineer,45000,B
    109,Samson,Admin,50000,A
    110,Quinlan,Manager,40000,A
    111,Joseph,Manager,40000,B
    112,Axel,Sales,60000,B
    113,Robert,Manager,40000,A
    114,Cairo,Engineer,45000,A
    115,Gavin,Ceo,100000,D
    116,Vaughan,Manager,40000,B
    117,Drew,Engineer,45000,D
    118,Quinlan,Admin,50000,B
    119,Gabriel,Engineer,45000,A
    120,Palmer,Ceo,100000,A' > ${g_WORK_DIR%/}/employee.csv

    # To support Beeline, uploading into HDFS
    _log "INFO" "Uploading csv files into HDFS ..."
    hdfs dfs -mkdir /tmp/hive_workspace
    hdfs dfs -chmod -R 777 /tmp/hive_workspace
    hdfs dfs -put -f ${g_WORK_DIR%/}/*.csv /tmp/hive_workspace/

    #_log "INFO" "executing hive queries under ${_dbname} database... kinit may require"
    _log "INFO" "Generating SQLs against ${_dbname} database... "
    _sql="${_sql}
CREATE TABLE IF NOT EXISTS sample_07 (
  code string,
  description string,
  total_emp int,
  salary int )
  ROW FORMAT DELIMITED
  FIELDS TERMINATED BY '\t'
  STORED AS TextFile;
LOAD DATA INPATH '/tmp/hive_workspace/sample_07.csv' OVERWRITE into table sample_07;
CREATE TABLE IF NOT EXISTS sample_07_orc stored as orc as select * from sample_07;
CREATE TABLE IF NOT EXISTS sample_08 (
  code string ,
  description string ,
  total_emp int ,
  salary int )
  ROW FORMAT DELIMITED
  FIELDS TERMINATED BY '\t'
  STORED AS TextFile;
LOAD DATA INPATH '/tmp/hive_workspace/sample_08.csv' OVERWRITE into table sample_08;
CREATE EXTERNAL TABLE IF NOT EXISTS emp_stage (
  empid int,
  name string,
  designation string,
  Salary int,
  department string)
  row format delimited
  fields terminated by ','
  location '/tmp/emp_stage_data';
LOAD DATA INPATH '/tmp/hive_workspace/employee.csv' OVERWRITE into table emp_stage;
CREATE TABLE IF NOT EXISTS emp_part_bckt (
  empid int,
  name string,
  designation  string,
  salary int)
  PARTITIONED BY (department String)
  clustered by (empid) into 2 buckets
  stored as orc;
set hive.exec.dynamic.partition=true;
set hive.exec.dynamic.partition.mode=nonstrict;
set hive.enforce.bucketing = true;
INSERT OVERWRITE TABLE emp_part_bckt PARTITION(department) SELECT empid, name,designation,salary,department FROM emp_stage;
CREATE TABLE IF NOT EXISTS census(
  ssn int,
  name string,
  city string,
  email string)
  row format delimited
  fields terminated by ',';
LOAD DATA INPATH '/tmp/hive_workspace/census.csv' OVERWRITE into table census;
CREATE TABLE IF NOT EXISTS census_clus(
  ssn int,
  name string,
  city string,
  email string)
  clustered by (ssn) into 8 buckets;
set hive.enforce.bucketing=true;
INSERT OVERWRITE TABLE census_clus select * from census;
"
# create table sample_07_id like sample_07; -- to create an identical table
# select INPUT__FILE__NAME, code from sample_08;
# select INPUT__FILE__NAME, empid from emp_part_bckt where department='D';
# set hive.exec.max.dynamic.partitions.pernode=4;
# set hive.exec.max.created.files=100000;

    if [ -s /var/log/hadoop/hdfs/hdfs-audit.log ]; then
        _log "INFO" "Adding SQL for importing /var/log/hadoop/hdfs/hdfs-audit.log."
        _file_size=`stat -c"%s" /var/log/hadoop/hdfs/hdfs-audit.log`
        if [ -n "$_file_size" ] && [ $(( 1024 * 1024 * 1024 )) -lt $_file_size ]; then
            _log "WARN" "/var/log/hadoop/hdfs/hdfs-audit.log file size () is larger than 1GB so that not importing"
        else
            sed -r 's/([0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9] [0-9][0-9]:[0-9][0-9]:[0-9][0-9],[0-9][0-9][0-9]|FSNamesystem.audit:) /\1\t/g' /var/log/hadoop/hdfs/hdfs-audit.log > ${g_WORK_DIR%/}/hdfs-audit.csv
            hdfs dfs -put -f ${g_WORK_DIR%/}/hdfs-audit.csv /tmp/hive_workspace/

            _sql="${_sql}
CREATE TABLE IF NOT EXISTS hdfs_audit (
  datetime_str STRING,
  log_class STRING,
  allowed STRING,
  ugi STRING,
  ip STRING,
  cmd STRING,
  src STRING,
  dst STRING,
  perm STRING,
  proto STRING,
  callerContext STRING
)
ROW FORMAT DELIMITED
FIELDS TERMINATED BY '\t'
LINES TERMINATED BY '\n'
STORED AS TEXTFILE;
LOAD DATA INPATH '/tmp/hive_workspace/hdfs-audit.csv' OVERWRITE into table hdfs_audit;
"
        fi
    fi

    if which hbase &>/dev/null; then
        _log "INFO" "Creating HBase table 'emp_review' with hbase shell..."
        # TODO: HBase doesn't seem to have 'create table if not exists' statement
        echo "create 'emp_review','review'" | hbase shell &> /tmp/hive_dummies_hbase_$USER.out
        if ! grep -q 'Here is some help for this command' /tmp/hive_dummies_hbase_$USER.out; then
            _log "INFO" "Adding SQLs for creating HBase external table 'emp_review' ..."
            _sql="${_sql}
    CREATE EXTERNAL TABLE IF NOT EXISTS emp_review(rowkey STRING, empid INT, score FLOAT)
    STORED BY 'org.apache.hadoop.hive.hbase.HBaseStorageHandler'
    WITH SERDEPROPERTIES ('hbase.columns.mapping' = ':key, review:empid, review:score')
    TBLPROPERTIES ('hbase.table.name' = 'emp_review');
    INSERT INTO emp_review select concat_ws('-',cast(empid as string),cast(CURRENT_TIMESTAMP as string)), empid, cast(rand() * 100 as int) from emp_stage;
"
        fi
    fi

    # TODO: no good way to find if druid is installed and use *hive2*
    if false; then
        _log "INFO" "Adding SQLs for creating a Druid table..."
        # https://jp.hortonworks.com/blog/sub-second-analytics-hive-druid/
        #set hive.druid.metadata.uri=jdbc:mysql://db.example.com/druid_benchmark;
        #set hive.druid.indexer.partition.size.max=9000000;
        #set hive.druid.indexer.memory.rownum.max=100000;
        #set hive.tez.container.size=16000;
        #set hive.tez.java.opts=-Xmx10g -XX:MaxDirectMemorySize=1024g -Duser.timezone="America/New_York";
        #set hive.llap.execution.mode=none;

        # NOTE: not sure if cast(from_unixtime( is needed for __time
        _sql="${_sql}
CREATE TABLE IF NOT EXISTS hdfs_audit_month
STORED BY 'org.apache.hadoop.hive.druid.DruidStorageHandler'
TBLPROPERTIES ('druid.datasource' = 'hdfs_audit_day', 'druid.segment.granularity' = 'MONTH', 'druid.query.granularity' = 'DAY')
AS
SELECT
 cast(from_unixtime(unix_timestamp(datetime_str, 'yyyy-MM-dd HH:mm:ss,SSS')) as timestamp) as `__time`,
 allowed,
 ugi,
 cmd
FROM
 hdfs_audit;
"
    fi

    _log "INFO" "Executing SQLs..."
    ${_cmd} -e "${_sql}"

    if which sqoop &>/dev/null; then
        _log "INFO" "Check (PostgreSQL) JDBC driver. If postgresql-9*jdbc4.jar exists, start Sqoop Import job..."
        if ls -l /usr/hdp/current/sqoop-client/lib/postgresql-9*jdbc4.jar; then
            _ambari="`sed -nr 's/^hostname ?= ?([^ ]+)/\1/p' /etc/ambari-agent/conf/ambari-agent.ini`"
            _log "INFO" "Importing ambari.alert_history on $_ambari into hive ..."
            sqoop import --connect "jdbc:postgresql://${_ambari}:5432/ambari" --username "ambari" --password "bigdata" --null-string "\\\\N" --null-non-string "\\\\N" --hive-drop-import-delims --hive-import --hive-database ${_dbname} --hive-table ambari_alert_history --delete-target-dir --target-dir /apps/hive/warehouse/${_dbname}.db/ambari_alert_history --m 1 --query "select * from ambari.alert_history where \$CONDITIONS order by alert_id desc limit 100" --verbose &> /tmp/hive_dummies_sqoop_$USER.out
        fi
    fi

    # NOTE: hive (1) returns ArrayIndexOutOfBoundsException if transactional is true and 'orc.bloom.filter.columns' is not '*'
    _log "INFO" "Completed!
    NOTE: ACID needs Orc, buckets, transactional=true, also testing bloom filter, like below:
    ${_cmd} -e \"USE ${_dbname};ALTER TABLE emp_part_bckt SET TBLPROPERTIES ('transactional'='true', 'orc.create.index'='true', 'orc.bloom.filter.columns'='*');TRUNCATE TABLE emp_part_bckt;INSERT INTO TABLE emp_part_bckt PARTITION(department) SELECT empid, name,designation,salary,department FROM emp_stage;\"
    "
    # May need below too?
    #\""ANALYZE TABLE emp_part_bckt PARTITION(department) COMPUTE STATISTICS;ANALYZE TABLE emp_part_bckt COMPUTE STATISTICS for COLUMNS;\""

    _log "INFO" "Listing HDFS /apps/hive/warehouse/${_dbname}.db/"
    hdfs dfs -ls /apps/hive/warehouse/${_dbname}.db/*/
fi