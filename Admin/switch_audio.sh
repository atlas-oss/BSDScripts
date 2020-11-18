#!/bin/sh

DEV=$(rcctl get sndiod flags | tr -dc '0-9')

if [[ $DEV -ne $1 ]];
then
    rcctl set sndiod flags -f rsnd/$1
    rcctl restart sndiod
fi
