#!/bin/make

VMNAME := $(shell basename $$PWD)
DRIVE_CAP ?= 70G
EXTRA_DRIVES ?= 0
NET_TYPE ?= "localhost"
QEMU_ARGS ?= ""

rh-start: disks/nvme1.qcow2 install.sh
# disks/rh-boot.qcow2 is not an explicit dependency because it consumes
# .build/rh-boot.qcow2 for its creation. This, however, confuses GNU Make
# to go rebuild the qcow2 disk unnecessarily.
	[ -f disks/rh-boot.qcow2 ] || make disks/rh-boot.qcow2
	@bash ./install.sh start disks/rh-boot.qcow2 $(NET_TYPE) $(EXTRA_DRIVES) $(QEMU_ARGS)

start: disks/boot.qcow2 disks/nvme1.qcow2 install.sh
	@bash ./install.sh start $< $(NET_TYPE) $(EXTRA_DRIVES) $(QEMU_ARGS)

install: disks/boot.qcow2
	@bash ./install.sh install $< $(NET_TYPE) $(EXTRA_DRIVES) $(QEMU_ARGS)

.build/rh-boot.qcow2: anaconda-ks.cfg
	-@sudo rmdir .build 2>/dev/null
# Look up the prebuilt ISO
	source ../vm_lib.sh && find_iso && sudo livemedia-creator \
		--virt-uefi \
		--make-disk --qcow2 \
		--iso=$$ISO_FILE --ks=$< \
		--image-name=$$(basename $@) \
		--resultdir ./.build --arch x86_64
	sudo chown $$USER:$$USER .build

disks/rh-boot.qcow2: .build/rh-boot.qcow2
	sudo mv .build/rh-boot.qcow2 $@
	sudo chown $$USER:$$USER $@

disks/%.qcow2:
	mkdir -p disks
	qemu-img create -f qcow2 $@ $(DRIVE_CAP)

# Simply embed the anaconda kickstart file into the ISO
boot.iso: anaconda-ks.cfg ../vm_lib.sh
# Look up the prebuilt ISO
	source ../vm_lib.sh && find_iso && sudo mkksiso --ks $< $$ISO_FILE $@

clean:
	-rm -f disks/*.qcow2
	-rm -f boot.iso
	-rm -f *.log
	-rm -rf .build
	-rm .netport
	-rm .netaddr

.PHONY: install start rh-start stop clean
