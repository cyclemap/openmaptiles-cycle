#!/bin/bash

set -e #exit on failure

exec &> >(tee --append "update.log")

#THE NEXT STEP:
#see here:  https://wiki.openstreetmap.org/wiki/Osmupdate#Assembling_an_OSM_Change_file
#you can create a "change file" (osc file) and use Osmosis or osm2pgsql to get that change file into postgres.
#we have to stop using quickstart.sh for that to work.

echo updating:  started at $(date)

rm --force data/north-america-new.osm.pbf
docker-compose run --rm import-osm osmupdate /import/north-america.osm.pbf /import/north-america-new.osm.pbf
mv --force data/north-america-new.osm.pbf data/north-america.osm.pbf

echo quickstart:  started at $(date)
time ./quickstart.sh north-america

echo done at $(date)
echo "====================================================================="

date=$(date +%Y-%m-%d)
file="tiles-$date-northamerica-14.mbtiles"
echo "mv data/tiles.mbtiles data-tileserver/$file && ln -sf $file data-tileserver/tiles.mbtiles && docker restart tileserver-gl"

