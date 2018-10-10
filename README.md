Generate Vagrant Base box from RHEL Official Cloud Image
========================================================

I wanted a VagrantBox for VirtualBox, created from the RHEL 7 qcow2 image that had the minimal changes needed to make it work.

The basic changes to the original disk image are taken from this article
http://docs.vagrantup.com/v2/boxes/base.html

A quick summary of changes made:

*  add `vagrant` user (uid:900/gid:900) with password `vagrant`
*  add [vagrant insecure ssh public key][1] to `vagrant` account
*  give `vagrant` full password-less sudo access without requiring a tty
*  change root's password to `vagrant`
*  turn off DNS check on SSHD to speed up logins
*  add biosdevname binary for Vagrant networking
*  add VirtualBox guest exensions

OSX Prereqs
-----------

* VirtualBox
* Vagrant
* brew install qemu


Build/Deploy
------------

1. Download an official RHEL cloud image from the RedHat network (RHN). ( https://access.redhat.com/downloads/content/69/ver=/rhel---7/7.1/x86_64/product-downloads )

2. Create the vagrant box from the qcow2.
<PRE>
git clone https://github.com/tkilloren/rhel_kvm2vagrant.git
cd rhel_vagrant_box
cp ~/Downloads/${imagename} ./
./CreateVagrantBox.sh ${imagename}
</PRE>

3. Upload the image to Openstack object store.


What's the script really doing?
-------------------------------

At a high level, it boots from a copy of the orginal qcow2 image to mount and modify another pristine copy that is then packaged into the VagrantBox.

1. Convert qcow2 image into two copies that are in the VirtualBox Disk Image format (vdi).  One will be used to build the vbox guest additions, mount the other copy, and then inject the changes.
2. Create a virtual box machine that boots from one copy, and mount the cloud-init iso, the guest-additions iso, and the copy that will be used for the vagrant box.
3. Boot the machine so that cloud-init runs a script to compile the vbox guest additions, insert them in the box image and add the vagrant changes.
4. Unmount the box disk image. Build a new vbox machine that will never boot that is then used by `vagrant package` to create the vagrant box.


Debugging Tips
--------------

Power on the builder vbox-machine, login as root pw:vagrant, and watch the clould-init progress:
<PRE>
tail -f /var/log/cloud-init.log
</PRE>

Validate VBox bins/modules are copied:
<PRE>
ls /mnt/lib/modules/$(uname -r)/misc
ls /mnt/opt/VBox*
ls -l /mnt/sbin/mount.vboxsf
</PRE>

Testing Box
-----------
<PRE>
vagrant box add rhel-guest-image-7.1-20150224.0.x86_64.box --name rhel_7 --force
vagrant init rhel_7
vagrant up
vagrant ssh
</PRE>


FAQ
---

*Q:* Why not use an image builder, such as Packer.io, or Kiwi, or, et cetera?<BR>
*A:* The goal is to use the pre-build RedHat KVM guest image in QEMU-KVM environments. The downside is that there is no RHEL Vagrant/VirtualBox option for doing testing on a laptop against an equivalent image.  This project creates a Vagrant Box from the official image, with just the minimal changes and addtions to make it work with Vagrant.

Issues
------

*  The image mounts `sda` or `sdb` on different runs. (XFS uuid issue?). Need to make this determanistic so cloud-init doesn't fail.

Resources
---------

*  http://docs.openstack.org/image-guide/content/ch_converting.html
*  http://www.perkin.org.uk/posts/create-virtualbox-vm-from-the-command-line.html
*  http://docs.vagrantup.com/v2/boxes/base.html
*  http://docs.vagrantup.com/v2/cli/package.html
*  https://www.virtualbox.org/manual/ch08.html
*  https://forums.virtualbox.org/viewtopic.php?f=7&p=78127
*  https://help.github.com/enterprise/11.10.340/admin/articles/installing-virtualbox-guest-additions/
*  http://msutic.blogspot.com/2013/07/how-to-detach-storage-device-from.html
*  http://www.linuxquestions.org/questions/linux-security-4/selinux-preventing-ssh-login-with-~-ssh-authorized_keys-4175469538/

[1]: https://github.com/mitchellh/vagrant/tree/master/keys
