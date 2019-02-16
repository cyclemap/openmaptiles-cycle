#!/bin/bash

set -e #exit on failure

exec >>update.log 2>&1

directory=updates
configFile=update-state.conf

echo "====================================================================="
echo "starting $(date)"

wget \
	--recursive --no-directories --no-parent --no-clobber \
	--no-verbose \
	--directory-prefix=$directory \
	--reject-regex='\?' \
	https://download.geofabrik.de/north-america-updates/000/002/

rm --force $directory/index.html

fromVersion=$(grep update-state= $configFile |
	sed 's/.*=//g')

toVersion=$(cd $directory && ls *.osc.gz |
	sort --numeric-sort --reverse |
	head --lines=1 |
	sed 's/.osc.gz//' )

echo updating from $fromVersion to $toVersion

if [[ $fromVersion < $toVersion ]]; then

	osmium cat -o north-america.osm.pbf data/north-america.osm.pbf $(for((version=$fromVersion+1;version<=$toVersion;version++)); do echo updates/$version.osc.gz; done)

	mv --force north-america.osm.pbf data/north-america.osm.pbf

	sed -i "s/update-state=.*/update-state=$toVersion/" $configFile

fi

echo done updating

time ./quickstart.sh north-america

echo done
echo "====================================================================="

