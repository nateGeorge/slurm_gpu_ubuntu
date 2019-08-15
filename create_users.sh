#!/bin/bash

csvfile=Class_List_MSDS684_FW1_2019.csv
defaultsalt="deepdream"

# gets the fourth column from the csv, which is the id in this case
ids=$(csvtool namedcol "User ID" $csvfile  | sed '1d')
for id in $ids
do
  PASSWORD="$id$defaultsalt"
  echo $PASSWORD
  echo /storage/$id/
  sudo useradd $id -d /storage/$id/ -m -g faculty -p $(openssl passwd -1 ${PASSWORD}) -e $(date '+%Y-%m-%d' -d '+1 year') -s /bin/#!/usr/bin/env bash
  sudo sacctmgr -i create user name=$id account=students
done
