#!/bin/bash

# need to first authenticate for kerberos
# kpass can be set in ~/.bashrc or as an environment variable
{
echo $kpass | sudo kinit admin
} || {
  # if $kpass env variable does not exist, it will ask for the password
  sudo kinit admin
} || {
  # don't run script if auth fails
  echo "couldn't authenticate for kerberos; exiting"
  exit 1
}

# this should just be a file with a username on each newline
csvfile=del_users.csv

ids=$(csvtool col 1 $csvfile)

for id in $ids
do
  sudo ipa user-del $id
  # -i option: commit without asking for confirmation
  sudo sacctmgr -i delete user $id
  sudo rm -r /storage/$id
done
