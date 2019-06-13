#!/bin/bash

minimumSize=9000000000
locationName=north-america
pbfFile=$locationName.osm.pbf
newFile=$locationName-new.osm.pbf

set -e #exit on failure

exec &> >(tee --append "update.log")

#THE NEXT STEP:
#see here:  https://wiki.openstreetmap.org/wiki/Osmupdate#Assembling_an_OSM_Change_file
#you can create a "change file" (osc file) and use Osmosis or osm2pgsql to get that change file into postgres.
#we have to stop using quickstart.sh for that to work.

echo updating:  started at $(date)

rm --force data/$newFile
docker-compose run --rm import-osm osmupdate --verbose /import/$pbfFile /import/$newFile
mv --force data/$newFile data/$pbfFile

if [ $(stat --format=%s data/$pbfFile) -lt $minimumSize ]; then
	#sometimes the file is too small because something failed.  let's stop here because this needs fixing.
	echo $pbfFile file size too small.  expected minimum size of $minimumSize bytes.
	false
fi

echo updating:  done at $(date)
echo "====================================================================="

echo quickstart:  started at $(date)

time ./quickstart.sh $locationName

echo quickstart:  done at $(date)
echo "====================================================================="

date=$(date +%Y-%m-%d)
file="tiles-$date-northamerica-14.mbtiles"
mv data/tiles.mbtiles data-tileserver/$file && ln -sf $file data-tileserver/tiles.mbtiles && docker restart tileserver-gl

