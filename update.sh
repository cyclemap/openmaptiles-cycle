#!/bin/bash

source .env

#these won't do what we want because docker is doing all of the real work
#renice +20 -p $$ >/dev/null
#ionice -c3 -p $$

minimumSize=9500000000
#redownload=yes
#locationName=north-america
locationName=cyclemap
temporaryDownloadLocation=data/download-temporary.osm.pbf
temporaryDownloadLocation2=data/download-temporary2.osm.pbf
pbfFile=data/$locationName.osm.pbf
newFile=data/$locationName-new.osm.pbf
oldFile=data/$locationName-old.osm.pbf

set -e #exit on failure

#notify an external script that processing has started
if [ -e process.sh ]; then
	./process.sh
fi

exec &> >(tee >(\
	sed \
		--unbuffered \
		-e 's/$//g' \
		-e 's//\n/g' |
	grep \
		--text \
		--invert-match \
		--line-buffered \
		'^' \
	>>"logs/update.log"
))

function getFile() {
	url=$1
	rm --force $temporaryDownloadLocation
	wget --progress=bar:force:noscroll --output-document $temporaryDownloadLocation $url
}

function tools() {
	docker-compose run --rm openmaptiles-tools nice "$@"
}

if [[ $redownload == "yes" || ! -e $pbfFile ]]; then
	if [[ $locationName == "planet" ]]; then
		getFile https://ftpmirror.your.org/pub/openstreetmap/pbf/planet-latest.osm.pbf
		mv --force $temporaryDownloadLocation $pbfFile
	elif [[ $locationName == "cyclemap" ]]; then
		getFile https://download.geofabrik.de/north-america-latest.osm.pbf
		mv --force $temporaryDownloadLocation $temporaryDownloadLocation2
		getFile https://download.geofabrik.de/central-america-latest.osm.pbf
		rm --force $newFile
		tools osmosis --rb /$temporaryDownloadLocation2 --rb /$temporaryDownloadLocation --merge --wb /$newFile
		rm --force $temporaryDownloadLocation $temporaryDownloadLocation2
		mv --force $newFile $pbfFile
	else
		getFile https://download.geofabrik.de/$locationName-latest.osm.pbf
		mv --force $temporaryDownloadLocation $pbfFile
	fi
fi

if [[ "$locationName" != "planet" ]]; then
	grep -q 180 data/$locationName.bbox && { echo failure, we calculated a bad bounding box vaule.  probably because min zoom is zero?  delete the bbox file, it confuses systems; exit 1; }
else
	echo "====> : Skipping bbox calculation when generating the entire planet"
fi

echo updating:  started at $(date)
rm --force $newFile
tools osmupdate --verbose /$pbfFile /$newFile
mv --force $pbfFile $oldFile
mv --force $newFile $pbfFile

if [ $(stat --format=%s $pbfFile) -lt $minimumSize ]; then
	#sometimes the file is too small because something failed.  let's stop here because this needs fixing.
	echo $pbfFile file size too small.  expected minimum size of $minimumSize bytes.
	false
fi
echo updating:  done at $(date)

#THE NEXT STEP:
#see here:  https://wiki.openstreetmap.org/wiki/Osmupdate#Assembling_an_OSM_Change_file
#you can create a "change file" (osc file) and use Osmosis or osm2pgsql to get that change file into postgres.
#we have to stop using quickstart.sh for that to work.


echo "====================================================================="

echo quickstart:  started at $(date)

time ./quickstart.sh $locationName

echo quickstart:  done at $(date)
echo "====================================================================="

date=$(date +%Y-%m-%d)
file="tiles-$date-$locationName-$MAX_ZOOM.mbtiles"
mv data/tiles.mbtiles data-tileserver/$file && ln -sf $file data-tileserver/tiles.mbtiles &&
	docker restart tileserver-gl

