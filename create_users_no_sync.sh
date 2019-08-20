#!/bin/bash

# Creates users with base Linux and no UID/GID synchronization

# You should first create the students SLURM account:
# sudo sacctmgr create account students

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
    sudo chmod -R 700 /storage/$id
    sudo chown -R $id:$id /storage/$id
    sudo sacctmgr -i create user name=$id account=students
    # expire their password so it must be changed upon first login
    sudo passwd -e $id
    # set quota on storage drive
    sudo setquota -u $id 150G 150G 0 0 /storage
    sudo setquota -u $id 5G 5G 0 0 /
  fi
done
