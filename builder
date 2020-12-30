#!/bin/sh

if [ `id -u` -ne 0 ]
then
   echo "The builder need to be run as root."
   exit 1
fi

if [ -z $1 ]
then
    JAIL="122_amd64"
else
    JAIL=$1
fi

if [ $CONFIG == "Y" ]
then
    echo "WARNING: Every port will be reconfigured. Are you sure?"
    read sure
    if [ $sure == "Y" ]
    then
	poudriere options -c -j $JAIL -p PORTS -f /usr/local/etc/poudriere.d/port-list || (echo "Options sequence failed..." && exit 1)
    else
	echo "Okay, proceeding with bulk."
    fi
fi

poudriere bulk -j $JAIL -p PORTS -f /usr/local/etc/poudriere.d/port-list || (echo "Bulk sequence failed..." && exit 1)
