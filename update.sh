#!/bin/bash

source .env

#these won't do what we want because docker is doing all of the real work
#renice +20 -p $$ >/dev/null
#ionice -c3 -p $$

locationName=$1; shift
defaultBbox='-77.7,38.5,-76.7,39.5'
largeBbox='-160,-10,-30,55'
if [[ "$locationName" == "cyclemap-large" ]]; then
	bbox=$largeBbox
	minimumSize=15000000000
else
	bbox=$defaultBbox
	locationName=cyclemap-small
	minimumSize=500000000
fi

outputLocationName=$locationName


#redownload=yes
temporaryDownloadFile=data/temporary-download.osm.pbf
temporaryDownloadSummationFile=data/temporary-download-summation.osm.pbf
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
	egrep \
		--text \
		--invert-match \
		--line-buffered \
		'^' \
	>>"logs/update.log"
))

function getFile() {
	location=$1
	rm --force $temporaryDownloadFile
	wget --progress=bar:force:noscroll --output-document $temporaryDownloadFile "https://download.geofabrik.de/$location-latest.osm.pbf"
}
function addFile() {
	location=$1
	getFile "$location"
	rm --force $newFile
	tools osmosis --rb /$temporaryDownloadSummationFile --rb /$temporaryDownloadFile --merge --wb /$newFile
	rm --force $temporaryDownloadFile $temporaryDownloadSummationFile
	mv --force $newFile $temporaryDownloadSummationFile
}
function getFileList() {
	first=$1; shift
	getFile $first
	mv --force $temporaryDownloadFile $temporaryDownloadSummationFile

	for location in "$@"; do
		addFile $location
	done

	mv --force $temporaryDownloadSummationFile $pbfFile
}

function tools() {
	docker-compose run --rm --name=tools -e CENTER_ZOOM -e BBOX --volume $PWD/data-tileserver:/data-tileserver openmaptiles-tools nice "$@"
}

function link {
	ln --symbolic --force --relative "$@"
}

if [[ $redownload == "yes" || ! -e $pbfFile ]]; then
	if [[ $locationName == "cyclemap-small" ]]; then
		getFile north-america/us
		mv --force $temporaryDownloadFile $pbfFile
	elif [[ $locationName == "cyclemap-large" ]]; then
		getFileList north-america central-america south-america
	else
		getFile $locationName
		mv --force $temporaryDownloadFile $pbfFile
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

#pick a bounding box
#https://stackoverflow.com/a/50626221
sed -i "/BBOX=.*/ {n; :a; /BBOX=.*/! {N; ba;}; s/BBOX=.*/BBOX=$bbox/; :b; n; \$! bb}" .env

echo "====================================================================="

echo quickstart:  started at $(date)

time ./quickstart.sh $locationName

echo quickstart:  done at $(date)
echo "====================================================================="

#revert bounding box change
sed -i "/BBOX=.*/ {n; :a; /BBOX=.*/! {N; ba;}; s/BBOX=.*/BBOX=$defaultBbox/; :b; n; \$! bb}" .env

date=$(date --iso-8601)
file=data-tileserver/tiles-$date-$outputLocationName-$MAX_ZOOM.mbtiles
mv data/tiles.mbtiles $file
link $file data-tileserver/tiles-$outputLocationName.mbtiles


#combine all of the locations into one file
if [[ $locationName == "cyclemap-small" ]]; then
	
	mainFile=data-tileserver/tiles-$date-cyclemap-main.mbtiles
	largeFile=data-tileserver/tiles-cyclemap-large.mbtiles
	
	echo combining:  started at $(date)
	
	#cyclemap-large
	cp --dereference $largeFile $mainFile
	#cyclemap-small updates
	tools tilelive-copy /$file /$mainFile
	#overwrite bbox!
	CENTER_ZOOM=8 BBOX=$largeBbox tools mbtiles-tools meta-copy /$largeFile /$mainFile
	link $mainFile data-tileserver/tiles-main.mbtiles

	echo combining:  done at $(date)

elif [[ $locationName == "cyclemap-large" ]]; then
	link $file data-tileserver/tiles-main.mbtiles
fi

./restart-tileserver.sh

