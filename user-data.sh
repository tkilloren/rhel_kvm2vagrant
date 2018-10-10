#!/bin/bash -x
#==============================================================================
# USER-DATA (to be run from cloud-init)
#
# This script will mount a clean copy of an enterprise linux image and make
# the changes necessary to make it a diskimage for a VagrantBox
#
#==============================================================================

#----------------------------------------------------
# Change builder image's root password to `vagrant`
#----------------------------------------------------
echo 'vagrant' | passwd --stdin root

#----------------------------------------------------
# Fail if sdb gets mounted as root directory
##FIXME - non-determanistic mount situation;
#----------------------------------------------------
_TEMP=$(mount| grep '/dev/sdb1 on / type')
if [ $? -eq 0 ]; then
  exit 1
fi

#----------------------------------------------------
# Fix Network Device (RHEL 7.1 is eth already)
#
# biosdevname will name eth0 as enp0s3 on Vbox
# newer images don't have the udev rule for biosdevname
#----------------------------------------------------
_TEMP=$(ip a| grep 'enp0s3:')
if [ $? -eq 0 ]; then
  cd /etc/sysconfig/network-scripts/ && sed -i 's/eth0/enp0s3/g' ifcfg-eth0 && mv ifcfg-eth0 ifcfg-enp0s3
  ifdown enp0s3
  ifup enp0s3
fi

#----------------------------------------------------
# Register to Satellite
#
# Need to get packages to build vbox additions
##FIXME - this is the only Target-centric part
#----------------------------------------------------
ACTKEY='2-rhel7-2015r1-7da446918516284f447824fd3fb7c1a2'
rpm --import /etc/pki/rpm-gpg/RPM-GPG-KEY-redhat-release http://rhs.target.com/pub/TARGET-GPG-KEY
rpm -U http://rhs.target.com/pub/rhn-org-trusted-ssl-cert-1.0-1.noarch.rpm
rhnreg_ks --serverUrl=https://rhs.target.com/XMLRPC --activationkey=$ACTKEY --sslCACert=/usr/share/rhn/RHN-ORG-TRUSTED-SSL-CERT --force hostname vagrant

#----------------------------------------------------
# Build Guest extensions
#----------------------------------------------------
yum install -y gcc kernel-devel-$(uname -r)
mkdir /addons_iso
mount /dev/sr1 /addons_iso
cd /addons_iso
sh ./VBoxLinuxAdditions.run --keep --target /root

#----------------------------------------------------
# Mount the clean copy of the disk image
#----------------------------------------------------
_TEMP=$(mount -o nouuid /dev/sdb1 /mnt)
if [ $? -ne 0 ]; then
  exit 1
fi

#----------------------------------------------------
# Fix Network Device
#
# biosdevname will name eth0 as enp0s3 on Vbox
# newer images don't have the biosdevname udev rul
#----------------------------------------------------
_TEMP=$(ip a| grep 'enp0s3:')
if [ $? -eq 0 ]; then
  cd /etc/sysconfig/network-scripts/ && sed -i 's/eth0/enp0s3/g' ifcfg-eth0 && mv ifcfg-eth0 ifcfg-enp0s3
fi

#----------------------------------------------------
# Vagrant needs biosdevname for doing network stuff
#
# Only copy binary because we don't want udev rule
#----------------------------------------------------
yum install -y biosdevname
cp /usr/sbin/biosdevname /mnt/usr/sbin/biosdevname

#----------------------------------------------------
# Copy GuestAdditions installers and helper apps
#----------------------------------------------------
rsync -azvh /root/ /mnt/root
rsync -azvh /opt/VBoxGuestAdditions-* /mnt/opt/


#----------------------------------------------------
# Run installer/fixes in chroot env
#----------------------------------------------------
(
cat << __CHROOT__
#!/bin/bash -x

# This will create the symlinks to the addons
cd /root
./install.sh install --force

# Disable Cloud-init (timeout waiting for datasource was delaying sshd)
##FIXME - just reduce the timeouts of cloud-init instead of turning off
echo 'datasource_list: [None]' >>/etc/cloud/cloud.cfg

# Fix Sudoers conf
echo 'vagrant ALL=(ALL) NOPASSWD: ALL' >>/etc/sudoers
sed -i 's/^Defaults\s*requiretty//g' /etc/sudoers

# Fix SSHD conf
echo 'UseDNS no' >>/etc/ssh/sshd_config
sed -i 's/^PasswordAuthentication\s*no/PasswordAuthentication yes/g' /etc/ssh/sshd_config
sed -i 's/^GSSAPIAuthentication\s*yes/GSSAPIAuthentication no/g' /etc/ssh/sshd_config

# Set root's password to `vagrant`
sed -i 's/root:!!:/root:\$6\$Pn5YQ.FU\$eyPHq3Y3sJ1OkrPfJOFRIkC3d91rbMPVlT9IRuBER4ZRkyRod9Kh7pr7U5.MOpbkqqRm0MdrAHxrOx0vTW21Q.:/' /etc/shadow

# Add `vagrant` user and change password to `vagrant`
groupadd -g 900 vagrant
useradd  -u 900 -g 900 -c 'Vagrant User' -m vagrant
sed -i 's/vagrant:!!:/vagrant:\$6\$Pn5YQ.FU\$eyPHq3Y3sJ1OkrPfJOFRIkC3d91rbMPVlT9IRuBER4ZRkyRod9Kh7pr7U5.MOpbkqqRm0MdrAHxrOx0vTW21Q.:/' /etc/shadow

# Setup Vagrant ssh key
mkdir -p /home/vagrant/.ssh
echo 'ssh-rsa AAAAB3NzaC1yc2EAAAABIwAAAQEA6NF8iallvQVp22WDkTkyrtvp9eWW6A8YVr+kz4TjGYe7gHzIw+niNltGEFHzD8+v1I2YJ6oXevct1YeS0o9HZyN1Q9qgCgzUFtdOKLv6IedplqoPkcmF0aYet2PkEDo3MlTBckFXPITAMzF8dJSIFo9D8HfdOV0IAdx4O7PtixWKn5y2hMNG0zQPyUecp4pzC6kivAIhyfHilFR61RGL+GPXQ2MWZWFYbAGjyiYJnAmCP3NOTd0jMZEnDkbUvxhMmBYSdETk1rRgm+R4LOzFUGaHqHDLKLX+FIPKcF96hrucXzcWyLbIbEgE98OHlnVYCzRdK8jlqm8tehUc9c9WhQ== vagrant insecure public key' >> /home/vagrant/.ssh/authorized_keys
chmod 0700 /home/vagrant/.ssh
chmod 0600 /home/vagrant/.ssh/authorized_keys
chown -R 900:900 /home/vagrant
# Fix SELinux Context
chcon -R -t ssh_home_t /home/vagrant/.ssh
__CHROOT__
) > /mnt/root/chroot.sh
chmod a+xr /mnt/root/chroot.sh
chroot /mnt /root/chroot.sh 2>&1


#----------------------------------------------------
# Copy Kernel Modules
#
# Do after install.sh -- it will delete them if they are there already
#----------------------------------------------------
rsync -azvh /lib/modules/`uname -r` /mnt/lib/modules/


#----------------------------------------------------
# We're done here.  Power off machine to signal that
# it's time to continue.
#----------------------------------------------------
sleep 3
poweroff
