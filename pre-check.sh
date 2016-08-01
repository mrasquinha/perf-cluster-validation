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

while read line; do
  if [[ $line =~ ^cldb-nodes:(.*) ]]; then
    # generate cldb.nodes
    cldbnode=$line
    cldbnode=$(echo "$cldbnode" | sed 's/^.*://g') 
    echo "$cldbnode" | grep -v '^$' | tr -d ' ' > /tmp/cldb.nodes
    echo "$cldbnode" | grep -v '^$' | tr -d ' '> /tmp/nodes.txt
  elif [[ $line =~ ^data-nodes:(.*) ]]; then
    # generate data.nodes
    nodelist=$line
    nodelist=$(echo "$nodelist" | sed 's/^.*://g') 
    if [[ $nodelist =~ "," ]]; then        #semicolon seperated
      tmp=$(echo "$nodelist" | tr ',' '\n' | tr -d ' ')
    elif [[ $nodelist =~ " " ]]; then      #semicolon seperated
      tmp=$(echo "$nodelist" | tr ' ' '\n' | grep -v '^$')
    else                              # simple regex
      tmp=$nodelist
    fi
    for node in "${tmp[@]}"; do
      if [[ $node =~ "[" ]]; then         # if regex
        node=$(echo "$node" | sed 's/\[/{/g' | sed 's/\]/}/g' | sed 's/-/../g')
        node=`eval "eval "echo $node`     #expand regex
        echo "$node" | tr ' ' '\n' | grep -v '^$' | tr -d ' ' >> /tmp/nodes.txt
        echo "$node" | tr ' ' '\n' | grep -v '^$' | tr -d ' ' >> /tmp/data.nodes
      else
        echo "$node" | grep -v '^$' | tr -d ' ' >> /tmp/nodes.txt
        echo "$node" | grep -v '^$' | tr -d ' ' >> /tmp/data.nodes
      fi
    done
  fi
done < $configFile

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

