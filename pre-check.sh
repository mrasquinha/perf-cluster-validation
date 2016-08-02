#!/bin/bash
# Mitchelle Rasquinha July 25th 2016
# MapR Technologies
# A series of system configuration checks on all nodes of a cluster prior
# to MapR software installation. 

function usage() {
  echo "Usage: ./pre-check.sh -c <config_file>"
}

basedir=`pwd`
root_pass="mapr"
configFile=""

source $basedir/util.sh

while getopts ":c:" opt; do
  case $opt in
    c) configFile=${OPTARG} ;;
    *) usage ; exit 1 ;;
  esac
done


# Make sure config exists and can be read by current user
if [[ -f $configFile && -r $configFile ]]; then
  echo "Using config file: $configFile"
else
  usage
  print_error "Config file not specified or readable: $configFile" 
fi

# Clear the existing cluster files
rm -f /tmp/nodes.txt
rm -f /tmp/cldb.nodes
rm -f /tmp/data.nodes
rm -f groups

generate_node_lists $configFile

# Stupidity checks
if [[ ! -s /tmp/nodes.txt || ! -s /tmp/cldb.nodes || ! -s /tmp/data.nodes ]]; then
  print_error "Invalid cluster configuration $nodelist $cldbnode"
fi

# Make sure user has root access on cluster
for node in `cat /tmp/nodes.txt`; do
  if [ $(id -u) != "0" ]; then
    print_error "Node not reachable $node"
  fi
done


# Setup clush
$basedir/setup_clush.sh -c /tmp/cldb.nodes -d /tmp/data.nodes -n /tmp/nodes.txt

# Generate hw audit report
$basedir/hw_report.sh -c $configFile

# Package dependencies if any in the scripts
#$basedir/chech_pkg_dep.sh

# Run basic benchmark tests
#$basedir/run_tests.sh

