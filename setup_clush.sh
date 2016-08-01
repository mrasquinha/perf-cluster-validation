#!/bin/bash
# Mitchelle Rasquinha July 25th 2016
# MapR Technologies
# Script check if cluster shell is installed
# updates the groups for the cluster
# Make sure cldb.node and $dataFile exist

source util.sh
function usage() {
  echo "Usage: ./setup_clush.sh -c <cldbnodes_file> -d <datanodes_file> -n <nodes_file>"
  exit 1
}

cldbFile=""
dataFile=""
nodesFile=""

while getopts ":c:d:n:" opt; do
  case $opt in
    c) cldbFile=${OPTARG} ;;
    d) dataFile=${OPTARG} ;;
    n) nodesFile=${OPTARG} ;;
    *) usage ;;
  esac
done

# Stupidity checks
if [[ ! -f $nodesFile || ! -f $cldbFile || ! -f $dataFile || \
  ! -r $nodesFile || ! -r $cldbFile || ! -r $dataFile || \
  ! -s $nodesFile || ! -s $cldbFile || ! -s $dataFile ]]; then
  usage
fi

for node in `cat $cldbFile`; do
  if ! type clush > /dev/null ; then
    print_warn "Clush not found. Installing"
    yum -y install clustershell
  else
    echo "Clush found. Updated groups files"
  fi
done

# generate groups file
all_grp="all: "
for n in `cat $nodesFile`; do 
  all_grp+="$n "
done
echo $all_grp > groups

data_grp="data: "
for n in `cat $dataFile`; do 
  data_grp+="$n "
done
echo $data_grp >> groups
mv groups /etc/clustershell/

# Check if the setup works
is_setup=$(clush -a -b date 2>&1 > /dev/null)
if [[ -n $is_setup ]]; then
  if ! type sshpass > /dev/null ; then
    echo "sshpass not found. Installing"
    yum -y install sshpass
  fi
  rm -f /root/.ssh/id_rsa*
  rm -f /root/.ssh/authorized_keys

  ssh-keygen -t rsa -P '' -f /root/.ssh/id_rsa
  cat /root/.ssh/id_rsa.pub > /root/.ssh/authorized_keys
  for n in `cat $nodesFile`; do 
    sshpass -p "mapr" scp /root/.ssh/id_rsa* $n:/root/.ssh/
    sshpass -p "mapr" scp /root/.ssh/authorized_keys $n:/root/.ssh/
  done
fi

is_setup=$(clush -a -b date 2>&1 > /dev/null)
if [[ -n $is_setup ]]; then
  echo "FATAL: Script unable to setup clush"
  print_error "Error setting up passwordless ssh"
else
  echo "Clush setup complete"
  clush -a -b date
fi



