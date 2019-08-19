# slurm_gpu_ubuntu
Instructions for setting up a SLURM cluster using Ubuntu 18.04.3 with GPUs.  Go from a pile of hardware to a functional GPU cluster with job queueing and user management.

OS used: Ubuntu 18.04.3 LTS


# Overview
This guide will help you create and install a GPU HPC cluster with a job queue and user management.  The idea is to have a GPU cluster which allows use of a few GPUs by many people.  Using multiple GPUs at once is not the point here, and hasn't been tested.  This guide demonstrates how to create a GPU cluster for neural networks (deep learning) which uses Python and related neural network libraries (Tensorflow, Keras, Pytorch), CUDA, and NVIDIA GPU cards.  You can expect this to take you a few days up to a week.

## Outline of steps:

- Prepare hardware
- Install OSs
- Sync UID/GIDs or create slurm/munge users
- Install Software (Nvidia drivers, Anaconda and Python packages)
- Install/configure file sharing (NFS here; if using more than one node/computer in the cluster)
- Install munge/SLURM and configure
- User management

## Acknowledgements
This wouldn't have been possible without this [github repo](https://github.com/mknoxnv/ubuntu-slurm) from mknoxnv.  I don't know who that person is, but they saved me weeks of work trying to figure out all the conf files and services, etc.

# Preparing Hardware

If you do not already have hardware, here are some considerations:

Top-of-the-line commodity motherboards can handle up to 4 GPUs.  You should pay attention to PCI Lanes in the motherboard and CPU specifications.  Usually GPUs can take up to 16 PCI Lanes, and work fastest for data transfer when using all 16 lanes.  To use 4 GPUs in one machine, your motherboard should support at least 64 PCI Lanes, and CPUs should have at least 64 Lanes available.  M.2 SSDs can use PCI lanes as well, so it can be better to have a little more than 64 Lanes if possible.  The motherboard and CPU specs usually detail the PCI lanes.

We used NVIDIA GPU cards in our cluster, but many AMD cards [should now work](https://rocm.github.io/) with Python deep learning libraries now.

Power supply wattage is also important to consider, as GPUs can take a lot of Watts at peak power.

You only need one computer, but to have more than 4 GPUs you will need at least 2 computers.  This guide assumes you are using more than one computer in your cluster.

# Installing operating systems

Once you have hardware up and running, you need to install an OS.  From my research I've found Ubuntu is the top Linux distribution as of 2019 (both for commodity hardware and servers), and is recommended.  Currently the latest long-term stability version is Ubuntu 18.04.3, which is what was used here.  LTS are usually better because they are more stable over time.  Other Linux distributions may differ in some of the commands.

I recommend creating a bootable USB stick and installing Ubuntu from that.  Often with NVIDIA, the installation freezes upon loading and [this fix](https://askubuntu.com/a/870245/458247) must be implemented.  Once the boot menu appears, choose Ubuntu or Install Ubuntu, then press 'e', then add `apci=off` directly after `quiet splash` (leaving a space between splish and apci).  Then press F10 and it should boot.

I recommend using [LVM](https://www.howtogeek.com/211937/how-to-use-lvm-on-ubuntu-for-easy-partition-resizing-and-snapshots/) when installing (there is a checkbox for it with Ubuntu installation), so that you can add and extend storage HDDs if needed.

**Note**: Along the way I used the package manager to update/upgade software many times (`sudo apt-get update` and `sudo apt-get upgrade`) followed by reboots.  If something is not working, this can be a first step to try to debug it.

## Synchronizing GID/UIDs
You may want to sync the GIDs and UIDs across machines.  This can be done with something like LDAP (install instructions [here](https://computingforgeeks.com/how-to-install-and-configure-openldap-ubuntu-18-04/) and [here](https://www.techrepublic.com/article/how-to-install-openldap-on-ubuntu-18-04/)).  However, in my experience, the only GIDs and UIDs that need to be synced are the slurm and munge users.  Other users can be created and run SLURM jobs without having usernames on the other machines in the cluster.

## Set up munge and slurm users and groups
Immediately after installing OS’s, you want to create the munge and slurm users and groups on all machines.  The GID and UID (group and user IDs) must match for munge and slurm across all machines.  If you have a lot of machines, you can use the parallel SSH utilities mentioned before.  There are also other options like NIS and NISplus.

On all machines we need the munge authentication service and slurm installed.  First, we want to have the munge and slurm users/groups with the same UIDs and GIDs.  In my experience, these are the only GID and UIDs that need synchronization for the cluster to work.  On all machines:

```
sudo adduser -u 1111 munge --disabled-password --gecos ""
sudo adduser -u 1121 slurm --disabled-password --gecos ""
```

#### You shouldn’t need to do this, but just in case, you could create the groups first, then create the users

```
sudo addgroup -gid 1111 munge
sudo addgroup -gid 1121 slurm

sudo adduser -u 1111 munge --disabled-password --gecos "" -gid 1111
sudo adduser -u 1121 slurm --disabled-password --gecos "" -gid 1121
```

When a user is created, a group with the same name is created as well.

The numbers don’t matter as long as they are available for the user and group IDs.  These numbers seemed to work with a default Ubuntu 18.04.3 installation.  It seems like by default ubuntu sets up a new user with a UID and  GID of UID + 1 if the GID already exists, so this follows that pattern.



## Installing software/drivers
Next you should install SSH.  Open a terminal and install: `sudo apt install openssh-server -y`.

Once you have SSH on the machines, you may want to use a [parallel SSH utility](https://www.tecmint.com/run-commands-on-multiple-linux-servers/) to execute commands on all machines at once.

### Synchronizing time
It's not a bad idea to sync the time across the servers.  [Here's how](https://knowm.org/how-to-synchronize-time-across-a-linux-cluster/).  One time when I set it up, it was ok, but another time the slurmctld service wouldn't start and it was because the times weren't synced.

### Install NVIDIA drivers
You will need the latest NVIDIA drivers install for their cards.  The procedure [currently is](http://ubuntuhandbook.org/index.php/2019/04/nvidia-430-09-gtx-1650-support/):

```
sudo add-apt-repository ppa:graphics-drivers/ppa
sudo apt-get update
sudo apt-get install nvidia-driver-430
```

The 430 driver will probably update soon.  You can use `sudo apt-cache search nvidia-driver*` to find the latest one, or go to the "Software & Updates" menu to install it.  For some reason, on the latest install I had to use aptitude to install it:

```
sudo apt-get install aptitude -y
sudo aptitude install nvidia-driver-430
```

But that still didn't seem to solve the issue, and I installed it via the "Software & Updates" menu under "Additional Drivers".

We also use [NoMachine](https://www.nomachine.com/) for remote GUI access.

## Install the Anaconda Python distribution.
Anaconda makes installing deep learning libraries easier, and doesn’t require installing CUDA/CuDNN libraries (which is a pain).  Anaconda handles the CUDA and other dependencies for deep learning libraries.

Download the distribution file:

```
cd /tmp
wget https://repo.anaconda.com/archive/Anaconda3-2019.03-Linux-x86_64.sh
```
You may want to visit https://repo.anaconda.com/archive/ to get the latest anaconda version instead, though you can use:


`conda update conda anaconda`

or

`conda update --all`

to update Anaconda once it’s installed.

Once the .sh file is downloaded, you should make it executable with

`sudo chmod +777 Anaconda3-2019.03-Linux-x86_64.sh`

then run the file:

`./Anaconda3-2019.03-Linux-x86_64.sh`

I chose yes for `Do you wish the installer to initialize Anaconda3
by running conda init?`.

Then you should do `source ~/.bashrc` to enable `conda` as a command.

If you chose `no` for the `conda init` portion, you may need to add some aliases to bashrc:

`nano ~/.bashrc`

Add the lines:

```
alias conda=~/anaconda3/bin/conda
alias python=~/anaconda3/bin/python
alias ipython=~/anaconda3/bin/ipython
```

Now install some anaconda packages:

```
conda update conda
conda install anaconda
conda install python=3.6
conda install tensorflow-gpu keras pytorch
```

The 3.6 install can take a while to complete (environment solving with conda is slow; it took about 15 minutes for me even on a fast computer -- the environment solving is definitely a big drawback of anaconda).  Not a bad idea to use tmux and put the `conda install python=3.6` in a `tmux` shell in case an SSH session is interrupted.

Python3.6 is the latest version with easy support for tensorflow and some other packages.

At this point you can use this code to test GPU functionality with this [demo code](https://raw.githubusercontent.com/keras-team/keras/master/examples/mnist_cnn.py), you could also use [this](https://stackoverflow.com/a/38580201/4549682).


# Install NFS (shared storage)
In order for SLURM to work properly, there must be a storage location present on all computers in the cluster with the same files used for jobs.  All computers in the cluster must be able to read and write to this directory.  One way to do this is with NFS, although other options such as OCFS2 exist.  Here we use NFS.

For the instructions, we will call the primary server `master` (the one hosting storage and the SLURM controller) and assume we have one worker node (another computer with GPUs) called `worker`.  We will also assume the username/groupname for the main administrative account on all machines is `admin:admin`.  I used the same username and group for the administrative accounts on all the servers.

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

The * is for IP addresses or hostnames.  In this case we allow anything, but you may want to limit it to your IPs/hostnames in the cluster.  Finally, start the NFS service:

`sudo systemctl start nfs-kernel-server.service`

It should start automatically upon restarts.

Now we can set up the clients.  On all worker servers:

```
sudo apt install nfs-common -y
sudo mkdir /storage
sudo chown admin:admin /storage
sudo mount master:/storage /storage
```

To make the drive mount upon restarts for the worker nodes, add this to fstab:

`master:/storage /storage nfs auto,timeo=14,intr 0 0`

This can be done like so:

`echo master:/storage /storage nfs auto,timeo=14,intr 0 0 | sudo tee -a /etc/fstab
`

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
