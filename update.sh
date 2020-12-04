#!/bin/bash

#these won't do what we want because docker is doing all of the real work
#renice +20 -p $$ >/dev/null
#ionice -c3 -p $$

locationName=north-america
pbfFile=$locationName.osm.pbf
newFile=$locationName-new.osm.pbf

set -e #exit on failure

exec &> >(tee --append "update.log")

#rm --force $pbfFile
#wget --progress=bar:force:noscroll --output-document $pbfFile https://download.geofabrik.de/$locationName-latest.osm.pbf
#mv --force $pbfFile data/$pbfFile

#THE NEXT STEP:
#see here:  https://wiki.openstreetmap.org/wiki/Osmupdate#Assembling_an_OSM_Change_file
#you can create a "change file" (osc file) and use Osmosis or osm2pgsql to get that change file into postgres.
#we have to stop using quickstart.sh for that to work.

echo updating:  started at $(date)
rm --force data/$newFile
docker-compose run --rm openmaptiles-tools osmupdate --verbose /import/$pbfFile /import/$newFile
mv --force data/$pbfFile{,.old}
mv --force data/$newFile data/$pbfFile

echo updating:  done at $(date)
echo "====================================================================="

echo quickstart:  started at $(date)

time ./quickstart.sh $locationName

echo quickstart:  done at $(date)
echo "====================================================================="

date=$(date +%Y-%m-%d)
file="tiles-$date-$locationName-14.mbtiles"
mv data/tiles.mbtiles data-tileserver/$file && ln -sf $file data-tileserver/tiles.mbtiles &&
	cp --recursive conf/cycle-style conf/tileserver-gl.json conf/viewer data-tileserver &&
	docker restart tileserver-gl

