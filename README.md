ion with easy support for tensorflow and some other packages.

At this point you can use this code to test GPU functionality with this [demo code](https://raw.githubusercontent.com/keras-team/keras/master/examples/mnist_cnn.py), you could also use [this](https://stackoverflow.com/a/38580201/4549682).


# Install NFS (shared storage)
In order for SLURM to work properly, there must be a storage location present on all computers in the cluster with the same files used for jobs.  All computers in the cluster must be able to read and write to this directory.  One way to do this is with NFS, although other options such as OCFS2 exist.  Here we use NFS.

For the instructions, we will call the primary server `master` (the one hosting storage and the SLURM controller) and assume we have one worker node (another computer with GPUs) called `worker`.  We will also assume the username/groupname for the main administrative account on all machines is `admin:admin`.  I used the same username and group for the administrative accounts on all the servers.

## Master node
On the master server, do:

`sudo apt install nfs-kernel-server -y`

Make a storage location:

`sudo mkdir /storage`

In my case, /storage was actually the mount point for a second HDD (LVM, which was expanded to 20TB).

Change ownership to your administrative username and group:

`sudo chown admin:admin /storage`

Next we need to add rules for the shared location.  This is done with:

`sudo nano /etc/exports`

Then adding the line:

`/storage    *(rw,sync,no_root_squash)`

The * is for IP addresses or hostnames.  In this case we allow anything, but you may want to limit it to your IPs/hostnames in the cluster.  In fact, it wasn't working for me unless I explicitly set the IPs of the clients here.  You have to have a separate entry for each IP.  Mine ended up looking like:

`/storage 172.xx.224.xx(rw,sync,no_root_squash,all_squash,anonuid=999999,anongid=999999) 172.xx.224.xx(rw,sync,no_root_squash,all_squash,anonuid=999999,anongid=999999)`

where the 'xx's are actual numbers.

Finally, start the NFS service:

`sudo systemctl start nfs-kernel-server.service`

It should start automatically upon restarts.

## Client nodes
Now we can set up the clients.  On all worker servers:

```
sudo apt install nfs-common -y
sudo mkdir /storage
sudo chown admin:admin /storage
sudo mount master:/storage /storage
```

To make the drive mount upon restarts for the worker nodes, add this to fstab (`sudo nano /etc/fstab`):

`master:/storage /storage nfs auto,timeo=14,intr 0 0`

This can be done like so:

`echo master:/storage /storage nfs auto,timeo=14,intr 0 0 | sudo tee -a /etc/fstab`

Now any files put into /storage from the master server can be seen on all worker servers connect via NFS.  The worker servers MUST be read and write.  If not, any sbatch jobs will give an exit status of 1:0.


# Preparing for SLURM installation
## Passwordless SSH from master to all workers

First we need passwordless SSH between the master and compute nodes.  We are still using `master` as the master node hostname and `worker` as the worker hostname.  On the master:

```
ssh-keygen
ssh-copy-id admin@worker
```

To do this with many worker nodes, you might want to set up a small script to loop through worker hostnames or IPs.

## Install munge on the master:
```
sudo apt-get install libmunge-dev libmunge2 munge -y
sudo systemctl enable munge
sudo systemctl start munge
```

Test munge if you like:
`munge -n | unmunge | grep STATUS`


Copy the munge key to /storage
```
sudo cp /etc/munge/munge.key /storage/
sudo chown munge /storage/munge.key
sudo chmod 400 /storage/munge.key
```

## Install munge on worker nodes:
```
sudo apt-get install libmunge-dev libmunge2 munge
sudo cp /storage/munge.key /etc/munge/munge.key
sudo systemctl enable munge
sudo systemctl start munge
```

If you want, you can test munge:
`munge -n | unmunge | grep STATUS`

## Prepare DB for SLURM

These instructions more or less follow this github repo: https://github.com/mknoxnv/ubuntu-slurm

First we want to clone the repo:
`cd /storage`
`git clone https://github.com/mknoxnv/ubuntu-slurm.git`

Install prereqs:
```
sudo apt-get install git gcc make ruby ruby-dev libpam0g-dev libmariadb-client-lgpl-dev libmysqlclient-dev mariadb-server -y
sudo gem install fpm
```

Next we set up MariaDB for storing SLURM data:
```
sudo systemctl enable mysql
sudo systemctl start mysql
sudo mysql -u root
```

Within mysql:
```
create database slurm_acct_db;
create user 'slurm'@'localhost';
set password for 'slurm'@'localhost' = password('slurmdbpass');
grant usage on *.* to 'slurm'@'localhost';
grant all privileges on slurm_acct_db.* to 'slurm'@'localhost';
flush privileges;
exit
```

Copy the default db config file:
`cp /storage/ubuntu-slurm/slurmdbd.conf /storage`

Ideally you want to change the password to something different than `slurmdbpass`.  This must also be set in the config file `/storage/slurmdbd.conf`.

# Install SLURM
## Download and install SLURM on Master

### Build the SLURM .deb install file
It’s best to check the downloads page and use the latest version (right click link for download and use in the wget command).  Ideally we’d have a script to scrape the latest version and use that dynamically.

You can use the -j option to specify the number of CPU cores to use for 'make', like `make -j12`.  `htop` is a nice package that will show usage stats and quickly show how many cores you have.

```
cd /storage
wget https://download.schedmd.com/slurm/slurm-19.05.2.tar.bz2
tar xvjf slurm-19.05.2.tar.bz2
cd slurm-19.05.2
./configure --prefix=/tmp/slurm-build --sysconfdir=/etc/slurm --enable-pam --with-pam_dir=/lib/x86_64-linux-gnu/security/ --without-shared-libslurm
make
make contrib
make install
cd ..
```

### Install SLURM
```
sudo fpm -s dir -t deb -v 1.0 -n slurm-19.05.2 --prefix=/usr -C /tmp/slurm-build .
sudo dpkg -i slurm-19.05.2_1.0_amd64.deb
```

Make all the directories we need:
```
sudo mkdir -p /etc/slurm /etc/slurm/prolog.d /etc/slurm/epilog.d /var/spool/slurm/ctld /var/spool/slurm/d /var/log/slurm
sudo chown slurm /var/spool/slurm/ctld /var/spool/slurm/d /var/log/slurm
```

Copy slurm control and db services:
```
sudo cp /storage/ubuntu-slurm/slurmdbd.service /etc/systemd/system/
sudo cp /storage/ubuntu-slurm/slurmctld.service /etc/systemd/system/
```

The slurmdbd.conf file should be copied before starting the slurm services:
`sudo cp /storage/slurmdbd.conf /etc/slurm/`

Start the slurm services:
```
sudo systemctl daemon-reload
sudo systemctl enable slurmdbd
sudo systemctl start slurmdbd
sudo systemctl enable slurmctld
sudo systemctl start slurmctld
```

If the master is also going to be a worker/compute node, you should do:

```
sudo cp /storage/ubuntu-slurm/slurmd.service /etc/systemd/system/
sudo systemctl enable slurmd
sudo systemctl start slurmd
```

## Worker nodes
Now install SLURM on worker nodes:

```
cd /storage
sudo dpkg -i slurm-19.05.2_1.0_amd64.deb
sudo cp /storage/ubuntu-slurm/slurmd.service /etc/systemd/system/
sudo systemctl enable slurmd
sudo systemctl start slurmd
```

## Configuring SLURM

Next we need to set up the configuration file.  Copy the default config from the github repo:

`cp /storage/ubuntu-slurm/slurm.conf /storage/slurm.conf`

Note: for job limits for users, you should add the [AccountingStorageEnforce=limits](https://slurm.schedmd.com/resource_limits.html) line to the config file.

Once SLURM is installed on all nodes, we can use the command

`sudo slurmd -C`

to print out the machine specs.  Then we can copy this line into the config file and modify it slightly.  To modify it, we need to add the number of GPUs we have in the system (and remove the last part which show UpTime).  Here is an example of a config line:

`NodeName=worker1 Gres=gpu:2 CPUs=12 Boards=1 SocketsPerBoard=1 CoresPerSocket=6 ThreadsPerCore=2 RealMemory=128846`

Take this line and put it at the bottom of `slurm.conf`.

Next, setup the `gres.conf` file.  Lines in `gres.conf` should look like:

```
NodeName=master Name=gpu File=/dev/nvidia0
NodeName=master Name=gpu File=/dev/nvidia1
```

If you have multiple GPUs, keep adding lines for each node and increment the last number after nvidia.

Gres has more options detailed in the docs: https://slurm.schedmd.com/slurm.conf.html (near the bottom).

Finally, we need to copy .conf files on **all** machines.  This includes the `slurm.conf` file, `gres.conf`, `cgroup.conf` , and `cgroup_allowed_devices_file.conf`.  Without these files it seems like things don’t work.

```
sudo cp /storage/ubuntu-slurm/cgroup* /etc/slurm/
sudo cp /storage/slurm.conf /etc/slurm/
sudo cp /storage/gres.conf /etc/slurm/
```

This directory should also be created on workers:
```
sudo mkdir -p /var/spool/slurm/d
sudo chown slurm /var/spool/slurm/d
```

After the conf files have been copied to all workers and the master node, you may want to reboot the computers, or at least restart the slurm services:

Workers:
`sudo systemctl restart slurmd`
Master:
```
sudo systemctl restart slurmctld
sudo systemctl restart slurmdbd
sudo systemctl restart slurmd
```

Next we just create a cluster:
`sudo sacctmgr add cluster compute-cluster`


## Configure cgroups

I think cgroups allows memory limitations from SLURM jobs and users to be implemented.  Set memory cgroups on all workers with:

```
sudo nano /etc/default/grub
And change the following variable to:
GRUB_CMDLINE_LINUX="cgroup_enable=memory swapaccount=1"
sudo update-grub
```
Finally at the end, I did one last `sudo apt upgate`, `sudo apt upgrade`, and `sudo apt autoremove`, then rebooted the computers:
`sudo reboot`


# User Management
## Adding users

Adding users can be done with Linux tools and SLURM commands.  It’s best to create a group for different user groups:

`sudo groupadd normal`

[Here is an example script](create_users.sh) to add users from a csv file.

Options used with `useradd`:

-d : sets home directory
-m : creates home directory if doesn’t exist
-g : adds user to group
-p: sets password
-e: sets expire date to 1 year from now
-s: sets shell


## Storage quotas
Next we need to set storage quotas for the user.  Follow this guide to set up the quota settings on the machine:
https://www.digitalocean.com/community/tutorials/how-to-set-filesystem-quotas-on-ubuntu-18-04

Then we can set quotas:

```bash
sudo setquota -u ngeorge 150G 150G 0 0 /storage
sudo setquota -u ngeorge 5G 5G 0 0 /
```

The `/dev/mapper/ubuntu--vg-root` is the LVM partition for the root drive `/`, and `/dev/disk/by-uuid/987d372b-9c96-4e62-af82-2d95dc6655b4` is the <file system> from `/etc/fstab` for the HDD /storage.

This sets the soft and hard limits to 150GB for /storage.


To see how much of the quota people are using:
```
sudo repquota -s /
sudo repquota -s /storage
```

The new users don’t seem to always show up until they have saved something on the drive.  You can also specifically look at one user with:

`sudo quota -vs ngeorge`


## Deleting SLURM users on expiration
The slurm account manager has no way to set an expiration for users.  So we use [this script](check_if_user_expired.sh) to check if the linux username has expired, and if so, we delete the slurm username.  This runs on a cronjob once per day.  At it to the crontab file with:

`sudo crontab -e`

Add this line:

`0 5 * * * bash /home/<username>/slurm_gpu_ubuntu/check_if_user_expired.sh
`
Obviously fix the path to where the script is, and change the username to yours.

# Troubleshooting
If trying to run a job with `sbatch` and the exit code is 1:0, this could mean your common storage location is not r/w accessible to all nodes.  Double-check that you can create files on the /storage location on all workers with something like `touch testing.txt`.

If the exit code is 2:0, this can mean there is some problem with either the location of the python executable, or some other error when running the python script.  Double check that the srun or python script is working as expected with the python executable specified in the sbatch job file.

If some workers are 'draining', down, or unavailable, you might try:

`sudo scontrol update NodeName=worker1 State=RESUME`

## Log files
When in doubt, you can check the log files.  The locations are set in the slurm.conf file, and are `/var/log/slurmd.log` and `/var/log/slurmctld.log` by default.  Open them with `sudo nano /var/log/slurmctld.log`.  To go to the bottom of the file, use ctrl+_ and ctrl+v.


## Node is stuck draining (drng from `sinfo`)
This has happened due to the memory size in slurm.conf being higher than actual memor size.  Double check the memory from `free -m` or `sudo slurmd -C` and update slurm.conf on all machines in the cluster.  Then run `sudo scontrol update NodeName=worker1 State=RESUME`

## Nodes are not visible upon restart
After restarting the master node, sometimes the workers aren't there. I've found I often have to do `sudo scontrol update NodeName=worker1 State=RESUME` to get them working/available.


## Taking a node offline
The best way to take a node offline for maintenance is to drain it:
`sudo scontrol update NodeName=worker1 State=DRAIN Reason='Maintenance'`

Users can see the reason with `sinfo -R`


## Testing GPU load
Using `watch -n 0.1 nvidia-smi` will show the GPU load in real-time.  You can use this to monitor jobs as they are scheduled to make sure all the GPUs are being utilized.




## Setting account options
You may want to limit jobs or submissions.  Here is how to set attributes (-1 means no limit):
```bash
sudo sacctmgr modify account students set GrpJobs=-1
sudo sacctmgr modify account students set GrpSubmitJobs=-1
sudo sacctmgr modify account students set MaxJobs=-1
sudo sacctmgr modify account students set MaxSubmitJobs=-1
```


# Better sacct

`sacct --format=jobid,jobname,state,exitcode,user,account`

More on sacct [here](https://slurm.schedmd.com/sacct.html).


# Changing IPs
If the IP addresses of your machines change, you will need to update these in the file `/etc/hosts` on all machines and `/etc/exports` on the master node.  It's best to restart after making these changes.

# NFS directory not showing up
Check the service is running on the master node:
`sudo systemctl status nfs-kernel-server.service`

If it is not working, you may have a syntax error in your /etc/exports file.  Rebooting after getting this working is a good idea.  Not a bad idea to reboot the client computers as well.

Once you have the service running on the master node, then see if you can manually mount the drive on the clients:

`sudo mount master:/storage /storage`

If it is hanging here, try mounting on the master server:

`sudo mkdir /test`
`sudo mount master:/storage /test`

If this works, you might have an issue with ports being blocked or other connection issues between the master and clients.

# Running a demo file
