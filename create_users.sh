#!/bin/bash

csvfile=Class_List_MSDS684_FW1_2019.csv
defaultsalt="deepdream"

# gets the fourth column from the csv, which is the id in this case
ids=$(csvtool namedcol "User ID" $csvfile  | sed '1d')
for id in $ids
do
  if id "$id" > /dev/null 2>&1; then
    # if user exists already, do nothing
    :
  else
    PASSWORD="$id$defaultsalt"
    echo $PASSWORD
    echo /storage/$id/
    sudo useradd $id -d /storage/$id/ -m -g students -p $(openssl passwd -1 ${PASSWORD}) -e $(date '+%Y-%m-%d' -d '+1 year +30 days') -s /bin/bash
    # make their home folder only readable to them and not other students
    sudo chmod +700 /storage/$id
    sudo sacctmgr -i create user name=$id account=students
  fi
done
