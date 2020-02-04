#!/bin/bash

# checks if a slurm user should be deleted.  This happens if the user
# saccmgr options: -n = no header, -P = parsable2 (pipe delimited)
# csvcut is from csvkit; install with conda or pip: conda install csvkit
slurm_users=$(sacctmgr list user -n -P | csvcut -d '|' -c 1)
for u in $slurm_users
do
  if id "$u" > /dev/null 2>&1; then
    echo $u
    echo 'user still exists'
  else
    # user id doesn't exist anymore; delete from slurm
    echo $u
    echo 'user no longer exists, deleting slurm username'
    sudo sacctmgr -i delete user name=$u
    sudo rm -r /storage/$u
  fi
done
