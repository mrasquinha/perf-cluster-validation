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

mapr_install=$(grep "MAPR_CLUSTER_INSTALL=" $configFile | sed 's/MAPR_CLUSTER_INSTALL=//g')
mapr_install_roles=$(grep "MAPR_CLUSTER_INSTALL_ROLES=" $configFile | sed 's/MAPR_CLUSTER_INSTALL_ROLES=//g')
if [[ -z $mapr_install || -z $mapr_install_roles ]]; then
  echo "Set MAPR_CLUSTER_INSTALL=<path_to_install_sripts>"
  echo "Set MAPR_CLUSTER_INSTALL_ROLES=<path_to_roles_file> in config"
  print_error "Missing mapr_installation path."
else
  if [[ ! -f $mapr_install_roles || ! -r $mapr_install_roles ]]; then
    print_error "MAPR install roles file missing or not readable $mapr_install_roles"
  fi
fi


echo "Cluster Validation `date`"

# 1. Verify mapr is not already installed and cluster has no zombie processes
sep='====================================================================='
if ps axo pid=,stat=  | grep Z ; then
  print_exit "Found zombie processes"
fi

if pgrep mfs ; then
  print_warn "Existing mapr installation found. Uninstall using cluster install scripts"
  $mapr_install/mapr_setup.sh -c=$mapr_install_roles -u -f
  sleep 5
fi

if [ -d /opt/mapr ]; then
  print_warn "Existing mapr installation found. Uninstall using cluster install scripts"
  $mapr_install/mapr_setup.sh -c=$mapr_install_roles -u -f
  sleep 5
fi

# 2. Verify Hardware
# probe for system info ###############
echo "#################### Begin Hardware audits ################################"
clush $parg "echo DMI Sys Info:; dmidecode | grep -A2 '^System Information'"; echo $sep
clush $parg "echo DMI BIOS:; dmidecode | grep -A3 '^BIOS I'"; echo $sep

# probe for cpu info ###############
echo "Begin Verify CPU"
clush $parg "lscpu | grep -v -e op-mode -e ^Vendor -e family -e Model: -e Stepping: \
  -e BogoMIPS -e Virtual -e ^Byte -e '^NUMA node(s)'"|  sort -u ; echo $sep
echo "End Verify CPU"

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
  echo $sep

# probe for nic info ###############
echo "Begin Verify NIC"
clush $parg " lspci | grep -i ether"
clush $parg " ip link show | grep 'state UP' | gawk '{print \$2}' | tr -d ':'| xargs -l  ethtool | grep -e ^Settings -e Speed -e Duplex"
clush -a -B 'echo "for a in \`ls /sys/class/net/*/speed\`; \
do if [[ -n \$(cat \$a 2>/dev/null) ]]; then \
  echo -n \$a ; printf "%4s" ; cat \$a; \
fi; \
done" > /tmp/nicspeed'
clush -a -B "bash /tmp/nicspeed"
echo "End Verify NIC"

# probe for disk info ###############
clush $parg "echo 'Storage Controller: '; lspci | grep -i -e ide -e raid -e storage -e lsi"; echo $sep
clush $parg "echo 'SCSI RAID devices in dmesg: '; dmesg | grep -i raid | grep -i scsi" 2>/dev/null ; echo $sep
echo "Begin Verify Disks"
clush $parg "echo 'Block Devices: '; lsblk -id | awk '{print \$1,\$4}'|sort -u | nl"; echo $sep
clush $parg "echo 'Mount Disks: '; mount | grep sd[a-z] |sort -u "; echo $sep
echo "End Verify Disks"
# not checking for ip over ib; No IB on current perf clusters

echo
echo "#################### Begin OS Audits #####################################"
echo "Begin Verify OS"
clush $parg "cat /etc/*release | sort -u"; echo $sep
clush $parg "uname -srvm | fmt"; echo $sep
echo "End Verify OS"
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
clush $parg "stat -c %a /tmp | grep 1777 || echo /tmp permissions not 1777" ; echo $sep

#clush $parg 'echo JAVA_HOME is ${JAVA_HOME:-Not Defined!}'; echo $sep
clush $parg $parg2 'echo "Java Version: "; java -version || echo See java-post-install.sh'; echo $sep
echo Hostname IP addresses
clush $parg 'hostname -I'; echo $sep
echo DNS lookup
clush $parg 'host $(hostname -f)'; echo $sep
echo Reverse DNS lookup
clush $parg 'host $(hostname -i)'; echo $sep
echo Check for system wide nproc and nofile limits
clush $parg "grep -e nproc -e nofile /etc/security/limits.d/*nproc.conf /etc/security/limits.conf |grep -v ':#' "; echo $sep
echo Check for root ownership of /opt/mapr
clush $parg 'stat --printf="%U:%G %A %n\n" $(readlink -f /opt/mapr)'; echo $sep

echo Check for $serviceacct user specific open file and process limits
clush $parg "echo -n 'Open process limit(should be >=32K): '; su - $serviceacct -c 'ulimit -u'" ; echo $sep
clush $parg "echo -n 'Open file limit(should be >=32K): '; su - $serviceacct -c 'ulimit -n'" ; echo $sep
echo Check for $serviceacct users java exec permission and version
clush $parg $parg2 "echo -n 'Java version: '; su - $serviceacct -c 'java -version'"; echo $sep
