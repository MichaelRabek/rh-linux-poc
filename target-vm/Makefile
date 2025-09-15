#!/bin/make

VMNAME := $(shell basename $$PWD)
DRIVE_CAP ?= 70G
EXTRA_DRIVES ?= 0
NET_TYPE ?= "localhost"

.PHONY: start stop rh-install clean network

start:
	-virsh start $(VMNAME)
	virt-viewer target-vm >/dev/null 2>&1 &
	@echo
	@echo "Don't forget to either run \"shutdown -h now\" in the $(VMNAME)"
	@echo "or \"make stop\" here on the host when done working on the VM."
	@echo "Simply closing the monitor window will not shut the VM down."

stop:
	virsh shutdown $(VMNAME)

# This does not need a lock file because the virt-install command will refuse
# to run if the guest name 'target-vm' is already in use.
rh-install: disks/boot.qcow2 disks/nvme1.qcow2 rh-install.sh anaconda-ks.cfg
	@bash ./rh-install.sh $(NET_TYPE) $(EXTRA_DRIVES)

disks/%.qcow2:
	qemu-img create -f qcow2 $@ $(DRIVE_CAP)
# There is a potential problem with this and that is that it is
# dependant on SELinux
	chcon -t virt_image_t $@

clean:
	-virsh destroy target-vm
	-virsh undefine target-vm
	-rm -f disks/*.qcow2
