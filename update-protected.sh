#!/bin/bash

lockfile=.update.exclusivelock

#for use in a cron job where you want to exit if you can't lock

flock --wait 1 "$lockfile" ./update.sh

exitCode=$?
if [[ $exitCode == 1 ]]; then
	>&2 echo "could not lock $lockfile"
fi

