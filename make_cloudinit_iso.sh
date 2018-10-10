#!/bin/sh
#==================================================
# make_cloudinit_iso.sh
#
# Generate an iso of metadata for cloud-init.
# This uses the datasource type of 'NOCLOUD'.
#
# USAGE:
#       cloudinit-nocloud-iso.sh
#
# REQUIRES: sh,hdiutil,genisoimage
#
# CREATED: Mon Oct 13 19:18:25 CDT 2014
#==================================================

#========================================
# GLOBAL VARIABLES
#========================================

dir_data='./data'
iso_name='seed.iso'

instance='iid-builder00'
hostname='vagrant-builder'


#========================================
# FUNCTIONS
#========================================


#========================================
# MAIN ()
#========================================

#----------------------------------------
# 1) Make temp dir to store data files
#----------------------------------------
mkdir -p "${dir_data}"


#----------------------------------------
# 2) Create meta-data file
#----------------------------------------
(
cat << __TEMPLATE_EC2_METADATA__
instance-id: ${instance}
local-hostname: ${hostname}
__TEMPLATE_EC2_METADATA__
) > "${dir_data}"/meta-data


#----------------------------------------
# 3) Create user-data file
#----------------------------------------
cp user-data.sh "${dir_data}"/user-data


#----------------------------------------
# 4) Create a 'Universal' ISO with volume
# name of 'cidata'
#----------------------------------------
if [ -s ${iso_name} ]; then
  rm -f ${iso_name}
fi

if [ "$(uname -s)" = 'Darwin' ]; then
  echo OSX
  hdiutil makehybrid -iso -joliet -o "${iso_name}"\
   -default-volume-name cidata "${dir_data}"
else
  echo Linux
  genisoimage -joliet -rock -output "${iso_name}"\
   -volid cidata "${dir_data}"/user-data "${dir_data}"/meta-data
fi
