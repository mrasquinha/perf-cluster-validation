#!/bin/bash
# Mitchelle Rasquinha July 25th 2016
# MapR Technologies

function print_warn() {
  echo -e "\033[01;41;37mERROR: "$1" \033[0m"
}

function print_error() {
  print_warn "$1"
  exit 1
}

function generate_node_lists(){
local cfg=$1
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
done < $cfg

}
