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
