#!/bin/bash

if [ ! $# == 1 ]; then
  echo "Usage: ./main.sh <config_file>"
fi

function print_error() {
  echo -e "\033[01;41;37mERROR: $1 \033[0m"
  exit 1
}

basedir=`pwd`
configFile="$1"

# convert to absolute path if not already
#if [[ "$configFile" != */* ]]; then
#  configFile=$basedir/$configFile
#fi

# Make sure config exists and can be read by current user
if [[ -f $configFile && -r $configFile ]]; then
  echo "Using config file: $configFile"
else
  print_error "Config file not specified or readable: $configFile" 
fi

# Make sure only root can run our script
if [ "$(id -u)" != "0" ]; then
   echo "NOT ROOT change this"
   #print_error "This script must be run as root"
fi

# Parse config file
IFS=$'\n'
for line in $(cat $configFile); do
  if [[ $line =~ ^nodes:(.*) ]];
  then
    echo "Found nodelist $line"
  elif [[ $line =~ ^package-dependencies:(.*) ]];
  then
    echo "Found package list $line"
  fi
done

#config file must contain nodelist of the cluster and nodes must be reachable; nodelist may be regex

#Generate hw audit report

#package dependencies if any in the scripts


