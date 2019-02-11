#!/bin/bash

#this probably doesn't correctly create the data/docker-compose-config.yml file:  the bounding box and the name is incorrect.
#AREAS='district-of-columbia virginia maryland'; NAME=dc-metro
#for area in $AREAS; do make download-geofabrik area=$area && docker-compose run --rm import-osm osmconvert /import/$area.osm.pbf -o=/import/$area.o5m; done
#docker-compose run --rm import-osm osmconvert $(for area in $AREAS; do echo -n "/import/$area.o5m "; done) -o=/import/$NAME.osm.pbf
#rm --force data/*.o5m

#time ./quickstart.sh $NAME

#when updating the "layers" directory
	#time ./update-layers.sh

set -o errexit
set -o pipefail
set -o nounset

#do this if you change any mapping.yaml files.  though it's not usually enough.  docker-compose run --rm import-osm

make db-start
#this is lame, because it removes everything:  make forced-clean-sql
#clean is required for some reason
docker-compose run --rm openmaptiles-tools make clean
docker-compose run --rm openmaptiles-tools make
docker-compose run --rm import-sql
make psql-analyze
make generate-tiles

