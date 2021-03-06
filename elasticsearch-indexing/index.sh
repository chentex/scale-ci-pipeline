#!/bin/bash

set -exo pipefail

# Help
function help(){
  printf "\n"
  printf "Usage: export <options> $0\n"
  printf "\n"
  printf "Options supported, export them as environment variables:\n"
  printf "\t ES_SERVER=str,                    str=elasticsearch server url, default: ""\n"
  printf "\t ES_INDEX=str,                     str=elasticsearch index, default: perf_scale_ci\n"
  printf "\t JENKINS_USER=str,                 str=Jenkins user, default: ""\n"
  printf "\t JENKINS_API_TOKEN=str,            str=Jenkins API token to authenticate, default: ""\n"
  printf "\t JENKINS_BUILD_TAG=str,            str=jenkins job build tag, it's a built-in env var and is automatically set in Jenkins environment\n"
  printf "\t JENKINS_NODE_NAME=str,            str=jenkins job build tag, it's a built-in env var and is automatically set in Jenkins environment\n"
  printf "\t JENKINS_BUILD_URL=str,            str=jenkins job build url, it's a built-in env var and is automatically set in Jenkins environment\n"
  printf "\t BENCHMARK_STATUS_FILE=str,        str=path to the file with benchmark status reported using key=value pairs\n"
}

# Defaults
if [[ -z $ES_SERVER ]]; then
  echo "Elastic server is not defined, please check"
  help
  exit 1
fi
if [[ -z $ES_INDEX ]]; then
  export ES_INDEX=perf-scale-ci
fi
if [[ -z $JENKINS_USER ]] || [[ -z $JENKINS_API_TOKEN ]]; then
  echo "Jenkins credentials are not defined, please check"
  help
  exit 1
fi

# Generate a uuid
export UUID=$(uuidgen)

# Elasticsearch and jenkins credentials
export ES_SERVER=$ES_SERVER
export ES_INDEX=$ES_INDEX
export JENKINS_USER=$JENKINS_USER
export JENKINS_API_TOKEN=$JENKINS_API_TOKEN

# Jenkins job info
export JOB_NAME=$JOB_NAME
export BUILD_NUMBER=$BUILD_NUMBER
export BUILD_TAG=$JENKINS_BUILD_TAG
export NODE_NAME=$JENKINS_NODE_NAME
export BUILD_URL=$JENKINS_BUILD_URL

# Timestamp
timestamp=`date +"%Y-%m-%dT%T.%3N"`

# Get OpenShift cluster details
cluster_name=$(oc get infrastructure cluster -o jsonpath='{.status.infrastructureName}')
platform=$(oc get infrastructure cluster -o jsonpath='{.status.platformStatus.type}')
masters=$(oc get nodes -l node-role.kubernetes.io/master --no-headers=true | wc -l)
workers=$(oc get nodes -l node-role.kubernetes.io/worker --no-headers=true | wc -l)
workload=$(oc get nodes -l node-role.kubernetes.io/workload --no-headers=true | wc -l)
infra=$(oc get nodes -l node-role.kubernetes.io/infra --no-headers=true | wc -l)
cluster_version=$(oc get clusterversion -o jsonpath='{.items[0].status.desired.version}')
network_type=$(oc get network cluster  -o jsonpath='{.status.networkType}')
all=$(oc get nodes  --no-headers=true | wc -l)

# Get the status and duration of the run
JOB_STATUS=$(curl -k --user "$JENKINS_USER:$JENKINS_API_TOKEN" $BUILD_URL/api/json | jq '.result')
JOB_DURATION=$(curl -k --user "$JENKINS_USER:$JENKINS_API_TOKEN" $BUILD_URL/api/json | jq '.duration')
UPSTREAM_JOB=$(curl -k --user "$JENKINS_USER:$JENKINS_API_TOKEN" $BUILD_URL/api/json | jq '.actions[0].causes[].upstreamProject')
UPSTREAM_JOB_BUILD=$(curl -k --user "$JENKINS_USER:$JENKINS_API_TOKEN" $BUILD_URL/api/json | jq '.actions[0].causes[].upstreamBuild')

if [[ -f "$BENCHMARK_STATUS_FILE" ]]; then
  while read -u 11 line;do
  benchmark_name=$(echo $line | awk -F'=' '{print $1}')
  benchmark_status=$(echo $line | awk -F'=' '{print $2}')
  # Index data into elasticsearch
  curl -X POST -H "Content-Type: application/json" -H "Cache-Control: no-cache" -d '{
    "uuid" : "'$UUID'",
    "run_id" : "'${UPSTREAM_JOB}-${UPSTREAM_JOB_BUILD}'",
    "platform": "'$platform'",
    "master_count": '$masters',
    "worker_count": '$workers',
    "infra_count": '$infra',
    "workload_count": '$workload',
    "total_count": '$all',
    "cluster_name": "'$cluster_name'",
    "network_type": "'$network_type'",
    "cluster_version": "'$cluster_version'",
    "total_count": '$all',
    "build_number": '$BUILD_NUMBER',
    "job_name": '$JOB_NAME',
    "build_tag": "'$BUILD_TAG'",
    "node_name": "'$NODE_NAME'",
    "job_status": '$JOB_STATUS',
    "build_url": "'$BUILD_URL'",
    "upstream_job": '$UPSTREAM_JOB',
    "upstream_job_build": '$UPSTREAM_JOB_BUILD',
    "job_duration": "'$JOB_DURATION'",
    "benchmark_name": "'$benchmark_name'",
    "benchmark_status": "'$benchmark_status'",
    "timestamp": "'$timestamp'"
    }' $ES_SERVER/$ES_INDEX/_doc/
  done 11<$BENCHMARK_STATUS_FILE
else
  curl -X POST -H "Content-Type: application/json" -H "Cache-Control: no-cache" -d '{
    "uuid" : "'$UUID'",
    "run_id" : "'${UPSTREAM_JOB}-${UPSTREAM_JOB_BUILD}'",
    "platform": "'$platform'",
    "master_count": '$masters',
    "worker_count": '$workers',
    "infra_count": '$infra',
    "workload_count": '$workload',
    "total_count": '$all',
    "network_type": "'$network_type'",
    "cluster_version": "'$cluster_version'",
    "total_count": '$all',
    "build_number": '$BUILD_NUMBER',
    "job_name": '$JOB_NAME',
    "cluster_name": "'$cluster_name'",
    "build_tag": "'$BUILD_TAG'",
    "node_name": "'$NODE_NAME'",
    "job_status": '$JOB_STATUS',
    "build_url": "'$BUILD_URL'",
    "upstream_job": '$UPSTREAM_JOB',
    "upstream_job_build": '$UPSTREAM_JOB_BUILD',
    "job_duration": "'$JOB_DURATION'",
    "timestamp": "'$timestamp'"
    }' $ES_SERVER/$ES_INDEX/_doc/
fi
