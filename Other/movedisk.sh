#!/bin/sh

DST_MOUNT="/mnt/sysbackup"
STDOUT="/dev/stdout"

printf "movedisk v0.01\nThis is for OpenBSD ONLY!\nSource disk: "
read SRC_DISK
printf "Destination disk: "
read DST_DISK
printf "Partitionscheme [GPT/MBR]: "
read SCHEME

printf "\nConfiguration:\nSource: %s\nDestination: %s\nMountpoint: %s\nScheme: %s\n\nDoes this look correct? [y/n]" $SRC_DISK $DST_DISK $DST_MOUNT $SCHEME
read confirm

if [[ $confirm != "y" ]];
then
    echo "Aborting..."
    exit
fi

printf "\nAre you sure you want to continue? This will erase all data on %s! POSSIBLE DATA LOSS! [y/n]"
read continue

if [[ $continue == "y" ]];
then
    echo "You was warned... proceeding."
    create_mount;
    check_mount;
    move;
fi

create_mount() {
    echo "creating $DST_MOUNT..."
    mkdir -p $DST_MOUNT > $STDOUT
    if [[ $? != 0 ]] ; then
	echo "  $DST_MOUNT creation failed, aborting..."
	exit
    fi
}

check_mount() {
    mount | grep /dev/$SRC_DISK > $STDOUT
    if [[ $? != 0 ]];
    then
	echo "No partitions on $SRC_DISK seem to be mounted, aborting..."
	exit
    fi

    mount | grep /dev/$DST_DISK > $STDOUT
    if [[ $? != 1 ]];
    then
	echo "Looks like $DST_DISK is mounted, or there was an error, aborting..."
	exit
    fi

    mount | grep $DST_MOUNT
    if [[ $? != 1 ]];
    then
	echo "$DST_MOUNT is mounted or there was an error, aborting..."
	exit
    fi
}

move() {
    if [[ $SCHEME == "MBR" ]];
    then
	echo "Reinitializing $DST_DISK with MBR..."
	fdisk -iy $DST_DISK > $STDOUT
    elif [[ $SCHEME == "GPT" ]];
    then
	echo "Reinitializing $DST_DISK with GPT..."
	fdisk -iy -g -b 960 $DST_DISK > $STDOUT
    else
	echo "No valid scheme found, defaulting to GPT..."
	fdisk -iy -g -b 960 $DST_DISK > $STDOUT
    fi
    
    disklabel -d $DST_DISK > $STDOUT
    echo "Partitioning..."
    disklabel $SRC_DISK > - | (disklabel -R $DST_DISK -)

    PARTITIONS=`disklabel $SRC_DISK | grep ^\ \ [a-p] | sed s/\:.*// | sed s/\ \ //`
    
    for part in $PARTITIONS; do
        PARTINFO=`disklabel $SRC_DISK | grep \ \ $part\:`
        if [[ $PARTINFO != *4.2BSD* ]] ; then
            continue
        fi
        MOUNTDIR=`disklabel $SRC_DISK | grep \ \ $part\: | sed s/^.*#\ //`

        echo "checking $SRC_DISK$part mount point..."
        mount | grep \/dev\/$SRC_DISK$part > $STDOUT
        if [[ $? != 0 ]] ; then
            echo "  $SRC_DISK$part isn't mounted, won't be backed up"
            continue
        fi
        SRC_MOUNT=`mount | grep \/dev\/$SRC_DISK$part | sed s/^.*$SRC_DISC$part\ on\ // | sed s/\ type\ .*//`
        echo " ..found $SRC_MOUNT"

        # install a new file system and mount it
        echo "formatting $DST_DISK$part..."
        newfs $DST_DISK$part > $STDOUT

        echo "mounting /dev/$DST_DISK$part to $DST_MOUNT..."
        mount /dev/$DST_DISK$part $DST_MOUNT > $STDOUT
        if [[ $? != 0 ]] ; then
            echo "  mount failed, skipping $DST_DISK$part"
            continue
        fi

        echo "dumping $SRC_MOUNT onto $DST_MOUNT..."
        /sbin/dump -0au -f - $SRC_MOUNT | ( cd $DST_MOUNT ; /sbin/restore -rf - )

        if [[ $SRC_MOUNT = "/" && -f $DST_MOUNT/boot ]] ; then
            echo "writing boot on $DST_DISK..."
	    if [[ $SCHEME == "MBR" ]];
	    then
		/usr/mdec/installboot $DST_MOUNT/boot /usr/mdec/biosboot $DST_DISK > $STDOUT
	    else
		/usr/mdec/installboot $DST_MOUNT/boot /usr/mdec/biosboot $DST_DISK > $STDOUT	    fi
        fi

        if [[ $SRC_MOUNT = "/" && -f $DST_MOUNT/etc/fstab ]] ; then
            echo "replacing duid in $DST_MOUNT/etc/fstab..."
            cp $DST_MOUNT/etc/fstab $DST_MOUNT/etc/fstab.bak
            SRC_DUID=`disklabel $SRC_DISK | grep ^duid: | sed s/duid\:\ //`
            DST_DUID=`disklabel $DST_DISK | grep ^duid: | sed s/duid\:\ //`
            sed s/$SRC_DUID/$DST_DUID/ $DST_MOUNT/etc/fstab.bak > $DST_MOUNT/etc/fstab
         fi

        umount $DST_MOUNT > $STDOUT
        if [[ $? != 0 ]] ; then
            echo "there was an error unmounting $DST_MOUNT, aborting"
            exit
        fi

    done
}
