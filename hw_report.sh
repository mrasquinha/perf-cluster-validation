#!/bin/bash
# Mitchelle Rasquinha July 25th 2016
# MapR Technologies
# v1: These checks are mostly copied from cluster-audit PS tool
# Pre-requisite clust is installed and setup for nodes on this cluster

function usage() {
  echo "Usage: ./hw_report.sh -c <config_file>"
}

source $PWD/util.sh
configFile=""

while getopts ":c:" opt; do
  case $opt in
    c) configFile=${OPTARG} ;;
    *) usage ; exit 1 ;;
  esac
done

if [[ ! -f $configFile ]]; then
  usage
  print_error "Invalid configuration file $configFile"
fi

parg="-a -b"  #parg for clush; batch output
parg2="-B"      #batch + stderr
parg3="-u 30"

dependency_list=$(grep -e "^package-dependencies:" $configFile)
if [[ $dependency_list =~ ^package-dependencies:(.*) ]]; then
  # parse package dependencies
  dependency_list=$(echo "$dependency_list"| sed 's/^.*://g') 
  if [[ $dependency_list =~ "," ]]; then
    dependency_list=$(echo "$dependency_list" | tr ',' ' ')
  fi
fi

#Section to use existing mapr installation scripts
#mapr_install=$(grep "MAPR_CLUSTER_INSTALL=" $configFile | sed 's/MAPR_CLUSTER_INSTALL=//g')
#mapr_install_roles=$(grep "MAPR_CLUSTER_INSTALL_ROLES=" $configFile | sed 's/MAPR_CLUSTER_INSTALL_ROLES=//g')
#if [[ -z $mapr_install || -z $mapr_install_roles ]]; then
#  echo "Set MAPR_CLUSTER_INSTALL=<path_to_install_sripts>"
#  echo "Set MAPR_CLUSTER_INSTALL_ROLES=<path_to_roles_file> in config"
#  print_error "Missing mapr_installation path."
#else
#  if [[ ! -f $mapr_install_roles || ! -r $mapr_install_roles ]]; then
#    print_error "MAPR install roles file missing or not readable $mapr_install_roles"
#  fi
#fi


echo "Cluster Validation `date`"

# 1. Verify mapr is not already installed and cluster has no zombie processes
sep='====================================================================='
if ps axo pid=,stat=  | grep Z ; then
  print_exit "Found zombie processes"
fi

if pgrep mfs ; then
  print_warn "Existing mapr installation found. Uninstall using cluster install scripts"
  #Call before pre-check
  #$mapr_install/mapr_setup.sh -c=$mapr_install_roles -u -f
  #sleep 5
fi

if [ -d /opt/mapr ]; then
  print_warn "Existing mapr installation found. Uninstall using cluster install scripts"
  #Call before pre-check
  #$mapr_install/mapr_setup.sh -c=$mapr_install_roles -u -f
  #sleep 5
fi

# 2. Verify Hardware
# probe for system info ###############
echo "#################### Begin Hardware audits ################################"
clush $parg "echo DMI Sys Info:; dmidecode | grep -A2 '^System Information'"; echo $sep
clush $parg "echo DMI BIOS:; dmidecode | grep -A3 '^BIOS I'"; echo ""

echo '==================== Begin CPU Audits ==============================='
# probe for cpu info ###############
clush $parg "lscpu | grep -v -e op-mode -e ^Vendor -e family -e Model: -e Stepping: \
  -e BogoMIPS -e Virtual -e ^Byte -e '^NUMA node(s)'"|  sort -u ;
echo '====================== End CPU Audits ==============================='

# probe for mem/dimm info ###############
clush $parg "cat /proc/meminfo | grep -i ^memt | sort -u "; echo $sep
clush $parg "echo -n 'DIMM slots: ';  dmidecode -t memory |grep -c '^[[:space:]]*Locator:'"; echo $sep
clush $parg "echo -n 'DIMM count is: ';  dmidecode -t memory | grep -c '^[[:space:]]Size: [0-9][0-9]*'"; echo $sep
clush $parg "echo DIMM Details; dmidecode -t memory | \
  grep -v -e '^\s*Handle'| \
  grep -v -e '^\s*Total Width'| \
  grep -v -e '^\s*Form Factor'| \
  grep -v -e '^\s*Set:'| \
  grep -v -e '^\s*Asset Tag:'| \
  grep -v -e '^\s*Serial Number:'| \
  grep -v -e '^\s*Type Detail'| \
  grep -v -e '^\s*Manufacturer'| \
  grep -v -e '^\s*Part Number'| \
  grep -v -e '^\s*Locator'"
  echo ""

# probe for nic info ###############
echo '==================== Begin NIC Audits ==============================='
clush $parg " lspci | grep -i ether"
clush $parg " ip link show | grep 'state UP' | gawk '{print \$2}' | tr -d ':'| xargs -l  ethtool | grep -e ^Settings -e Speed -e Duplex"
clush -a -B 'echo "for a in \`ls /sys/class/net/*/speed\`; \
do if [[ -n \$(cat \$a 2>/dev/null) ]]; then \
  echo -n \$a ; printf "%4s" ; cat \$a; \
fi; \
done" > /tmp/nicspeed'
clush -a -B "bash /tmp/nicspeed"
echo '====================== End NIC Audits ==============================='

# probe for disk info ###############
clush $parg "echo 'Storage Controller: '; lspci | grep -i -e ide -e raid -e storage -e lsi"; echo $sep
clush $parg "echo 'SCSI RAID devices in dmesg: '; dmesg | grep -i raid | grep -i scsi" 2>/dev/null ; echo ""

echo '==================== Begin Disks Audits ============================='
clush $parg "echo 'Block Devices: '; lsblk -id | awk '{print \$1,\$4}'|sort -u | nl"; echo $sep
clush $parg "echo 'Mount Disks: '; mount | grep sd[a-z] |sort -u "
# not checking for ip over ib; No IB on current perf clusters
echo '====================== End Disks Audits ============================='

echo
echo '==================== Begin OS Audits ================================'
clush $parg "cat /etc/*release | sort -u"; echo $sep
clush $parg "uname -srvm | fmt"; echo ""
echo '===================== End OS Audits ================================='
clush $parg "echo Time Sync Check: ; date"; echo $sep
clush $parg "echo Required RPMs: ; rpm -q $dependency_list | grep 'is not installed' || echo All Required Installed" ; echo $sep
clush $parg "echo \"NTP status \"; service ntpd status 2>/dev/null| grep -o "Active.*since" | sed 's/since//g' "; echo $sep
clush $parg 'echo "NFS packages installed "; rpm -qa | grep -i nfs |sort -u' ; echo $sep

serviceacct="mapr"

# See https://www.percona.com/blog/2014/04/28/oom-relation-vm-swappiness0-new-kernel/
clush $parg "echo 'Sysctl Values: '; sysctl vm.swappiness net.ipv4.tcp_retries2 vm.overcommit_memory"; echo $sep
echo -e "/etc/sysctl.conf values should be:\nvm.swappiness = 1\nnet.ipv4.tcp_retries2 = 5\nvm.overcommit_memory = 0"; echo $sep
clush $parg "echo -n 'Transparent Huge Pages: '; cat /sys/kernel/mm/transparent_hugepage/enabled" ; echo $sep
clush $parg 'echo "Disk Controller Max Transfer Size:"; files=$(ls /sys/block/{sd,xvd}*/queue/max_hw_sectors_kb 2>/dev/null); for each in $files; do printf "%s: %s\n" $each $(cat $each); done'; echo $sep
clush $parg 'echo "Disk Controller Configured Transfer Size:"; files=$(ls /sys/block/{sd,xvd}*/queue/max_sectors_kb 2>/dev/null); for     each in $files; do printf "%s: %s\n" $each $(cat $each); done'; echo $sep
echo Check Mounted FS
clush $parg $parg3 "df -hT | cut -c22-28,39- | grep -e '  *' | grep -v -e /dev"; echo $sep
echo Check for nosuid mounts #TBD add noexec check
clush $parg $parg3 "mount | grep -e noexec -e nosuid | grep -v tmpfs |grep -v 'type cgroup'"; echo $sep

echo Check for /tmp permission
tmp_permission=$(clush $parg "stat -c %a /tmp"| grep -v 1777| grep -v "\-\-" | grep -v "\." )
if [[ -z $tmp_permission ]]; then 
  echo "/tmp permissions OK"
else
  print_warn "/tmp permissions not 1777"
fi
echo $sep


echo '================= Verify hostnames for nodes ========================'
# Verify hostnames on cluster
if [[ ! -f /tmp/nodes.txt ]]; then
  generate_node_lists $configFile
fi
# Needs password less ssh
for n in `cat /tmp/nodes.txt`; do
  ip=$(ssh $n hostname -I | tr -d ' ')
  if [[ "$ip" != "$n" ]]; then
    print_warn "Error in hostname setup for $n $ip"
  fi

  dns=$(ssh $n hostname -f | tr -d ' ')
  ip2=$(ssh $dns hostname -i | tr -d ' ')
  if [[ $ip2 != $n ]]; then
    print_warn "Error in hostname for ip $n $dns"
  fi
done
echo $sep

echo Check for system wide nproc and nofile limits
clush $parg "grep -e nproc -e nofile /etc/security/limits.d/*nproc.conf /etc/security/limits.conf |grep -v ':#' "; echo $sep

#pre-check should not have /opt/mapr
#echo Check for root ownership of /opt/mapr
#clush $parg 'stat --printf="%U:%G %A %n\n" $(readlink -f /opt/mapr)'; echo $sep

echo Check for $serviceacct user specific open file and process limits
clush $parg "echo -n 'Open process limit(should be >=32K): '; su - $serviceacct -c 'ulimit -u'" ; echo $sep
clush $parg "echo -n 'Open file limit(should be >=32K): '; su - $serviceacct -c 'ulimit -n'" ; echo $sep

echo Check for $serviceacct users java exec permission and version
recommended_java_version="1.8"
#echo $jversion
while read line ; do
  echo $line
  if [[ $line =~ "Java version" ]]; then 
    ver=$(echo "$line" | grep -o "\".*\"" | tr -d "\"" | grep -o -m 1 '[0-9]\.[0-9]')
    if [[ $ver < "$recommended_java_version" ]]; then
      print_warn "Java version less that $recommended_java_version"
    fi
  fi
done < <(clush $parg $parg2 "echo -n 'Java version: '; su - $serviceacct -c 'java -version'")
