#!/bin/bash

if [ -z "$1" ];then
	echo "./run_verdi.sh <name.fsdb>"
	exit 1
fi

FSDB_NAME=$1

if [ ! -f "$FSDB_NAME" ];then
	echo "ERROR:Cannot find file $FSDB_NAME"
	exit 1
fi

echo "Starting the fsdb file"

verdi -F ../filelist_vcs.f \
       	 +incdir+../rtl \
	 -ssf $FSDB_NAME 
