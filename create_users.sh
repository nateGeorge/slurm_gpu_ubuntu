#!/bin/bash

# You should first create the students SLURM account:
# sudo sacctmgr create account students

# need to first authenticate for kerberos
# kpass can be set in ~/.bashrc or as an environment variable

# the CSV file should have a header row, then values like:
#
# Name,ID,Email,User ID
# "George, Nathan C.",2915101,ngeorge@regis.edu,ngeorge01

# The script is run like:
# create_users.sh -f Class_List_MSDS684_FW1_2019.csv -c User ID -t
# options:
# -f : filename for CSV with usernames
# -c : column name for userid column
# -t : option for testing (if set, does not create users or directories);
# this is for testing if the csv and column name are correct

{
echo $kpass | kinit admin
} || {
  # if $kpass env variable does not exist, it will ask for the password
  kinit admin
} || {
  # don't run script if auth fails
  echo "couldn't authenticate for kerberos; exiting"
  exit 1
}

# test to ensure ipa connection works
res=ip
if ! [ $? -eq 0 ]; then
    echo 'connection to ipa failed; exiting'
    exit 1
fi

# default values for args
usernamecol="User ID"
testing=false

while [ "$1" != "" ]; do
case $1 in
  -f | --file )
  shift
  csvfile="$1"
  shift;;
  -t | --testing )
  testing=true
  shift;;
  -c | --usernamecol )
  shift
  usernamecol="$1"
  shift;;
esac
done

defaultsalt="deepdream"

# gets the fourth column from the csv, which is the id in this case
# you need to install csvtool for this to work: sudo apt install csvtool -y
# sed '1d' deletes the first line (the column label)
ids=$(csvtool namedcol "$usernamecol" $csvfile  | sed '1d')
if $testing
then
  echo "testing"
  echo $ids
else
  echo "creating new users"
  for id in $ids
  do
    # in case IDs are uppercase, convert to lowercase
    lc_id=$(echo "$id" | tr '[:upper:]' '[:lower:]')
    # some bug is causing the users to stick around even after sudo ipa user-del,
    # so skip this check to see if they exist
    # if id "$id" > /dev/null 2>&1; then
    #   # if user exists already, do nothing
    #   echo 'user already exists'
    #   :
    # else
    PASSWORD="$lc_id$defaultsalt"
    echo $PASSWORD
    echo /storage/$id/
    # for testing I also had to set the minimum password life to 0 hours:
    # ipa pwpolicy-mod global_policy --minlife 0
    # https://serverfault.com/a/609004/305991
    # sets user to expire in 1 year + 1 month, and the password is set to have already expired (so they must reset it upon logging in)
    echo $PASSWORD | ipa user-add $lc_id --first='-' --last='-' --homedir=/storage/$lc_id --shell=/bin/bash --password --setattr krbprincipalexpiration=$(date '+%Y-%m-%d' -d '+1 year +30 days')$'Z' --setattr krbPasswordExpiration=$(date '+%Y-%m-%d' -d '-1 day')$'Z'
    # make their home folder only readable to them and not other students
    sudo mkdir /storage/$lc_id
    # bashrc and profile were copied from the main accounts' home dir
    sudo cp /etc/skel/.profile /storage/$lc_id
    sudo cp /etc/skel/.bashrc /storage/$lc_id
    # only allow users to see their own directory and not others'
    sudo chmod -R 700 /storage/$lc_id
    # only allow users to use 4 of 6 GPUs at a time
    # -i option: commit without asking for confirmation (no y/N option)
    # MaxJobs -- max number of jobs that can run at once
    # MaxSubmitJobs -- Max number of jobs that can be submitted to the queue
    # MaxWall -- max number of minutes per job (set to 12 hours)
    sudo sacctmgr -i create user name=$lc_id account=students MaxJobs=4 MaxSubmitJobs=30 MaxWall=720
    # sudo sacctmgr -i modify user where name=$id set MaxJobs=4
    # fi
  done

  # for some reason it can't find the newly-created users, so have to put this in another loop
  for id in $ids
  do
    # in case IDs are uppercase, convert to lowercase
    lc_id=$(echo "$id" | tr '[:upper:]' '[:lower:]')
    sudo chown -R $lc_id:$lc_id /storage/$lc_id
    # set quota on storage drive
    sudo setquota -u $lc_id 150G 150G 0 0 /storage
    sudo setquota -u $lc_id 5G 5G 0 0 /
  done
fi