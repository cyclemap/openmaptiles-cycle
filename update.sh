#!/bin/bash

source .env

set -e #exit on failure

#these won't do what we want because docker is doing all of the real work
#renice +20 -p $$ >/dev/null
#ionice -c3 -p $$

#redownload=yes
quickstart=yes

locationName=$1; shift || true
defaultBbox='-77.7,38.5,-76.7,39.5' #lon lat bottom left, lon lat upper right
largeBbox='-180,-45,180,60'
if [[ "$locationName" == "cyclemaps-large" ]]; then
	fileList=(planet)
	bbox=$largeBbox
	minimumSize=50000 #mb
	./process-large.sh
	#the unit is:  days.  zoom 0..14
	#latitude and longitude			import	tiling	size gb
	#-45 to 60 and -160 to 70		3		10		74
	#-45 to 60 and -160 to 130		3		12		90
	#-45 to 60 and -180 to 180		3		16?		120?
else
	locationName=cyclemaps-small
	
	fileList=(north-america/us)
	bbox=$defaultBbox
	minimumSize=500 #mb
	./process.sh
fi

#this is a really loose requirement because we have NO CLUE how much of the disk is full of things that we're about to delete or write over
#if we just blew away everything, running out of disk space can still happen!
#first number is for the "main" or "large" file and 40gb for at least a bit of padding
diskSpaceRequired=$((120+40)) #gb

temporaryDownloadFile=data/temporary-download.osm.pbf
temporaryDownloadSummationFile=data/temporary-download-summation.osm.pbf
pbfFile=data/$locationName.osm.pbf
newFile=data/$locationName-new.osm.pbf
changeFile=data/changes.osc.gz
oldFile=data/$locationName-old.osm.pbf

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

function getFile {
	location=$1
	rm --force $temporaryDownloadFile
	if [ $location == "planet" ]; then root='https://planet.openstreetmap.org/pbf/'; else root='https://download.geofabrik.de/'; fi
	wget --progress=bar:force:noscroll --output-document $temporaryDownloadFile "$root$location-latest.osm.pbf"
}
function addFile {
	location=$1
	getFile "$location"
	rm --force $newFile
	tools osmosis --rb $temporaryDownloadSummationFile --rb $temporaryDownloadFile --merge --wb $newFile
	rm --force $temporaryDownloadFile $temporaryDownloadSummationFile
	mv --force $newFile $temporaryDownloadSummationFile
}
function getFileList {
	first=$1; shift
	getFile $first
	mv --force $temporaryDownloadFile $temporaryDownloadSummationFile

	for location in "$@"; do
		addFile $location
	done

	mv --force $temporaryDownloadSummationFile $pbfFile
}

function tools {
	#echo docker-compose run --rm --name=tools -e CENTER_ZOOM -e BBOX --volume $PWD/data-tileserver:/data-tileserver openmaptiles-tools nice "$@" >&2
	docker-compose run --rm --name=tools -e CENTER_ZOOM -e BBOX --volume $PWD/data-tileserver:/data-tileserver openmaptiles-tools nice "$@"
}

function link {
	ln --symbolic --force --relative "$@"
}

#either updates the input, or updates the input INTO the database

function updateInput {
	if [[ ! -e $pbfFile ]]; then
		redownload='yes'
	fi


	if [[ $redownload == "yes" ]]; then
		quickstart=yes
		getFileList ${fileList[@]}
	fi
	
	echo updating:  started at $(date)
	rm --force $newFile


	if [[ $quickstart == "yes" ]]; then
		tools osmupdate --verbose $pbfFile $newFile
	else
		#there is a bug here.  something about this does not work.  try:
			#tools osmupdate --verbose $pbfFile $newFile
			#now somehow diff pbfFile and newFile into changeFile
		tools osmupdate --verbose $pbfFile $changeFile
		make start-db
		make import-diff area=$locationName
		tools osmconvert $pbfFile $changeFile --out-pbf >$newFile 
	fi
	mv --force $pbfFile $oldFile
	mv --force $newFile $pbfFile


	if [ $(stat --format=%s $pbfFile) -lt ${minimumSize}000000 ]; then
		#sometimes the file is too small because something failed.  let's stop here because this needs fixing.
		echo $pbfFile file size too small.  expected minimum size of $minimumSize mb.
		false
	fi
	echo updating:  done at $(date)
}

#imports into the database (IF that wasn't already done by the last step), and generates tiles
#this step takes days for the whole planet

function mainGeneration {
	if [[ "$locationName" != "planet" ]]; then
		grep -q 180 data/$locationName.bbox && { echo failure, we calculated a bad bounding box vaule.  probably because min zoom is zero?  delete the bbox file, it confuses systems; exit 1; }
	else
		echo "====> : Skipping bbox calculation when generating the entire planet"
	fi

	#pick a bounding box
	#https://stackoverflow.com/a/50626221
	sed -i "/BBOX=.*/ {n; :a; /BBOX=.*/! {N; ba;}; s/BBOX=.*/BBOX=$bbox/; :b; n; \$! bb}" .env

	echo "====================================================================="

	echo $([[ $quickstart == "yes" ]] && echo quickstart || echo generating tiles):  started at $(date)

	if [[ $quickstart == "yes" ]]; then
		time ./quickstart.sh $locationName
	else
		time make generate-tiles-pg
		make stop-db
	fi

	echo $([[ $quickstart == "yes" ]] && echo quickstart || echo generating tiles):  done at $(date)
	echo "====================================================================="

	#revert bounding box change
	sed -i "/BBOX=.*/ {n; :a; /BBOX=.*/! {N; ba;}; s/BBOX=.*/BBOX=$defaultBbox/; :b; n; \$! bb}" .env

	date=$(date --iso-8601)
	file=data-tileserver/tiles-$date-$locationName-$MAX_ZOOM.mbtiles
	mv data/$locationName.mbtiles $file
	link $file data-tileserver/tiles-$locationName.mbtiles
}

#combine all of the locations into one file

function combineOutputs {
	if [[ $locationName == "cyclemaps-small" ]]; then
		
		mainFile=data-tileserver/tiles-$date-cyclemaps-main.mbtiles
		largeFile=data-tileserver/tiles-cyclemaps-large.mbtiles
		
		echo combining:  started at $(date)
		
		#cyclemaps-large
		cp --dereference $largeFile $mainFile
		#cyclemaps-small updates
		tools tilelive-copy $file $mainFile
		#overwrite bbox!
		CENTER_ZOOM=8 BBOX=$largeBbox tools mbtiles-tools meta-copy $largeFile $mainFile
		link $mainFile data-tileserver/tiles-main.mbtiles

		echo combining:  done at $(date)

	elif [[ $locationName == "cyclemaps-large" ]]; then
		link $file data-tileserver/tiles-main.mbtiles
	fi
}

fileSystemRemaining=$(df . | awk '{if ($1 != "Filesystem") print $4}')
if [[ "$fileSystemRemaining" -lt $(($diskSpaceRequired*1024*1024)) ]]; then
	echo not enough space left on device
	exit 1
fi

updateInput
mainGeneration
combineOutputs
./restart-tileserver.sh

