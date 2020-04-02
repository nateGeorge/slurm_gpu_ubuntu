# used for creating admin accounts, like faculty

# first authenticate for kerberos
# kpass can be set in ~/.bashrc or as an environment variable
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

id='ksorauf'
sudo mkdir /storage/$id
salt='deepdream'
PASSWORD="$id$salt"
echo $PASSWORD | ipa user-add $id --first='-' --last='-' --homedir=/storage/$id --shell=/bin/bash --password --setattr krbPasswordExpiration=$(date '+%Y-%m-%d' -d '-1 day')$'Z'
# add to admin group (change group name as necessary)
ipa group-add-member faculty --users=$id
# also should have the group have sudo privelages; see create_faculty_admin_sudo_group.sh
# https://serverfault.com/a/560237/305991


# create slurm user
sudo sacctmgr -i create user name=$id account=faculty
