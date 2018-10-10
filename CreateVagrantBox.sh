#!/bin/sh
#==============================================================================
# CreateVagrantBox.sh
#
# Generate a VagrantBox from RedHat's offical RHEL cloud-ready image.
#
# Requires: qemu-tools, VirtualBox, and Vagrant
#==============================================================================

#-------------------------------------------------------------------
# 0) Check input, setup variables, and clean up old runs
#-------------------------------------------------------------------
# Print Useage
if [ $# -eq 0 ]; then
  echo 'usage:'
  echo " $0 imagename.qcow2"
  exit 1
fi

command -v vagrant >/dev/null 2>&1 ||\
  { echo >&2 "I require 'vagrant' but it's not in path.  Aborting."; exit 1; }

command -v qemu-img >/dev/null 2>&1 ||\
  { echo >&2 "I require 'qemu-img' but it's not in path.  Aborting."; exit 1; }

command -v VBoxManage >/dev/null 2>&1 ||\
  { echo >&2 "I require 'VBoxManage' but it's not in path.  Aborting."; exit 1; }

# Setup Variables
name=${1}
base=$(basename ${name} '.qcow2')
builder="${base}.builder"

#..Delete existing builder machine.....
_temp=$(VBoxManage list vms | grep "${builder}" )
if [ $? -eq 0 ]; then
  _temp=$(VBoxManage list runningvms | grep "${builder}" )
  if [ $? -eq 0 ]; then
    VBoxManage controlvm "${builder}" poweroff
  fi
  VBoxManage unregistervm --delete "${builder}"
fi

#..Delete existing vagrant machine.....
_temp=$(VBoxManage list vms | grep "${base}" )
if [ $? -eq 0 ]; then
  _temp=$(VBoxManage list runningvms | grep "${base}" )
  if [ $? -eq 0 ]; then
    VBoxManage controlvm "${base}" poweroff
  fi
  VBoxManage unregistervm --delete "${base}"
fi

#-------------------------------------------------------------------
# 1) Make CloudInit iso that runs Vagrant edits script
#-------------------------------------------------------------------
echo '* Making cloud iso .......'
./make_cloudinit_iso.sh


#-------------------------------------------------------------------
# 2) Convert original qcow2 disk image to VirtalBox format
# do two calls so they have different vdi UUID's
#-------------------------------------------------------------------
echo '* Creating VDI disk images from qcow .......'
_temp=$(qemu-img convert -f qcow2 -O vdi ${base}.qcow2 ${base}.vdi 2>&1)
if [ $? -ne 0 ]; then
  echo "FAILED: ${_temp}"
  exit 1
fi
_temp=$(qemu-img convert -f qcow2 -O vdi ${base}.qcow2 ${builder}.vdi 2>&1)
if [ $? -ne 0 ]; then
  echo "FAILED: ${_temp}"
  exit 1
fi


#-------------------------------------------------------------------
# 3) Create VirtalBox Machine to edit pristine disk image copy
#-------------------------------------------------------------------
echo '* Creating Builder VBox Machine .......'

_temp=$(VBoxManage createvm --name ${builder} --ostype 'RedHat_64' --register 2>&1)
if [ $? -ne 0 ]; then
  echo "FAILED: ${_temp}"
  exit 1
fi
_temp=$(VBoxManage storagectl ${builder} --name 'IDE Controller' --add ide 2>&1)
if [ $? -ne 0 ]; then
  echo "FAILED: ${_temp}"
  exit 1
fi
_temp=$(VBoxManage storagectl ${builder} --name 'SATA Controller 1' --add sata \
       --controller IntelAHCI 2>&1)
if [ $? -ne 0 ]; then
  echo "FAILED: ${_temp}"
  exit 1
fi
#..Boot from builder image
_temp=$(VBoxManage storageattach ${builder} --storagectl 'IDE Controller'\
       --port 0 --device 0 --type hdd --medium ${builder}.vdi 2>&1)
if [ $? -ne 0 ]; then
  echo "FAILED: ${_temp}"
  exit 1
fi
#..Attach VirtualBox guest additions iso
_temp=$(VBoxManage storageattach ${builder} --storagectl 'SATA Controller 1'\
       --port 1 --device 0 --type dvddrive --medium '/Applications/VirtualBox.app/Contents/MacOS/VBoxGuestAdditions.iso' 2>&1)
if [ $? -ne 0 ]; then
  echo "FAILED: ${_temp}"
  exit 1
fi
_temp=$(VBoxManage modifyvm ${builder} --ioapic on 2>&1)
if [ $? -ne 0 ]; then
  echo "FAILED: ${_temp}"
  exit 1
fi
_temp=$(VBoxManage modifyvm ${builder} --boot1 disk --boot2 none --boot3 none\
       --boot4 none 2>&1)
if [ $? -ne 0 ]; then
  echo "FAILED: ${_temp}"
  exit 1
fi
_temp=$(VBoxManage modifyvm ${builder} --memory 1024 --vram 128 2>&1)
if [ $? -ne 0 ]; then
  echo "FAILED: ${_temp}"
  exit 1
fi


#-------------------------------------------------------------------
# 4) Power on builder vm to run cloud-init
#-------------------------------------------------------------------
echo '* Power on Builder VBox Machine .......'

#..Run Machine once so udev rules set builder diskimage as root uuid
VBoxManage startvm "$builder" --type headless
while [ 'VMState="running"' != "$(VBoxManage showvminfo --machinereadable ${builder} | grep 'VMState=')" ]; do
  echo "Builder not running, waiting..."
  sleep 8
done

##FIXME - this sleep is just a guess about how long a boot takes
sleep 30

#..Power off machine so the other diskimage can be added
VBoxManage controlvm "$builder" poweroff
while [ 'VMState="poweroff"' != "$(VBoxManage showvminfo --machinereadable ${builder} | grep 'VMState=')" ]; do
  echo "Shutting down, waiting..."
  sleep 8
done

echo '* Attaching modified disk image .......'
#..Attach image to edit
_temp=$(VBoxManage storageattach ${builder} --storagectl 'IDE Controller'\
       --port 1 --device 0 --type hdd --medium ${base}.vdi 2>&1)
if [ $? -ne 0 ]; then
  echo "FAILED: ${_temp}"
  exit 1
fi
#..Attach cloud-init iso
_temp=$(VBoxManage storageattach ${builder} --storagectl 'SATA Controller 1'\
       --port 0 --device 0 --type dvddrive --medium seed.iso 2>&1)
if [ $? -ne 0 ]; then
  echo "FAILED: ${_temp}"
  exit 1
fi

#..Start machine again to run cloud-init user-data script
VBoxManage startvm "$builder" --type gui

#..Wait for cloud-init script to shutoff the host
sleep 160
i=0
while [ 'VMState="poweroff"' != "$(VBoxManage showvminfo --machinereadable ${builder} | grep 'VMState=')" ]; do
  i=$((i+1))
  if [ ${i} -ge 10 ]; then
    echo 'Giving up...'
    exit 1
  fi
  echo "Shutting down, waiting..."
  sleep 8
done


#-------------------------------------------------------------------
# 5) Unmount disk image from Builder Machine
#-------------------------------------------------------------------
echo '* Unmount disk image from Builder VBox Machine .......'

_temp=$(VBoxManage storageattach ${builder} --storagectl 'IDE Controller'\
       --port 1 --device 0 --type hdd --medium none 2>&1)
if [ $? -ne 0 ]; then
  echo "FAILED: ${_temp}"
  exit 1
fi


#-------------------------------------------------------------------
# 6) Create New VirtalBox Machine to convert into Vagrant box
#-------------------------------------------------------------------
echo '* Create Vagrant VBox Machine .......'

_temp=$(VBoxManage createvm --name ${base} --ostype 'RedHat_64' --register 2>&1)
if [ $? -ne 0 ]; then
  echo "FAILED: ${_temp}"
  exit 1
fi
_temp=$(VBoxManage storagectl ${base} --name 'SATA Controller' --add sata \
       --controller IntelAHCI 2>&1)
if [ $? -ne 0 ]; then
  echo "FAILED: ${_temp}"
  exit 1
fi
#..Boot from builder image
_temp=$(VBoxManage storageattach ${base} --storagectl 'SATA Controller'\
       --port 0 --device 0 --type hdd --medium ${base}.vdi 2>&1)
if [ $? -ne 0 ]; then
  echo "FAILED: ${_temp}"
  exit 1
fi
_temp=$(VBoxManage modifyvm ${base} --ioapic on 2>&1)
if [ $? -ne 0 ]; then
  echo "FAILED: ${_temp}"
  exit 1
fi
_temp=$(VBoxManage modifyvm ${base} --boot1 dvd --boot2 disk --boot3 none\
       --boot4 none 2>&1)
if [ $? -ne 0 ]; then
  echo "FAILED: ${_temp}"
  exit 1
fi
_temp=$(VBoxManage modifyvm ${base} --memory 480 --vram 8 2>&1)
if [ $? -ne 0 ]; then
  echo "FAILED: ${_temp}"
  exit 1
fi


#-------------------------------------------------------------------
# 7) Generate Vagrant Base Box
#-------------------------------------------------------------------
echo '* Create VagrantBox from VBox Machine .......'
if [ -e ${base}.box ]; then
  rm -f ${base}.box
  sleep 1
fi

_temp=$(vagrant package --base ${base} --output ${base}.box 2>&1)
if [ $? -ne 0 ]; then
  echo "FAILED: ${_temp}"
  exit 1
fi


#-------------------------------------------------------------------
# 8) Clean up
#-------------------------------------------------------------------
echo '* Cleaning up .......'

#..Delete existing builder machine.....
_temp=$(VBoxManage list vms | grep "${builder}" )
if [ $? -eq 0 ]; then
  _temp=$(VBoxManage list runningvms | grep "${builder}" )
  if [ $? -eq 0 ]; then
    VBoxManage controlvm "${builder}" poweroff
  fi
  VBoxManage unregistervm --delete "${builder}"
fi

#..Delete existing vagrant machine.....
_temp=$(VBoxManage list vms | grep "${base}" )
if [ $? -eq 0 ]; then
  _temp=$(VBoxManage list runningvms | grep "${base}" )
  if [ $? -eq 0 ]; then
    VBoxManage controlvm "${base}" poweroff
  fi
  VBoxManage unregistervm --delete "${base}"
fi
