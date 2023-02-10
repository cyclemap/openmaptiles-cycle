#!/bin/bash

source .env

set -e #exit on failure

#these won't do what we want because docker is doing all of the real work
#renice +20 -p $$ >/dev/null
#ionice -c3 -p $$

#redownload=yes
quickstart=yes

locationName=$1; shift
defaultBbox='-77.7,38.5,-76.7,39.5' #lon lat bottom left, lon lat upper right
largeBbox='-160,-45,40,60'
if [[ "$locationName" == "cyclemap-large" ]]; then
	fileList=(north-america central-america south-america europe africa asia)
	bbox=$largeBbox
	minimumSize=50000 #mb
	./process-large.sh
else
	locationName=cyclemap-small
	
	fileList=(north-america/us)
	bbox=$defaultBbox
	minimumSize=500 #mb
	./process.sh
fi

outputLocationName=$locationName


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
	wget --progress=bar:force:noscroll --output-document $temporaryDownloadFile "https://download.geofabrik.de/$location-latest.osm.pbf"
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

function updatePbf {
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

if [[ ! -e $pbfFile ]]; then
	redownload='yes'
fi


if [[ $redownload == "yes" ]]; then
	quickstart=yes
	getFileList ${fileList[@]}
	updatePbf
else
	updatePbf
fi

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
	tools tilelive-copy $file $mainFile
	#overwrite bbox!
	CENTER_ZOOM=8 BBOX=$largeBbox tools mbtiles-tools meta-copy $largeFile $mainFile
	link $mainFile data-tileserver/tiles-main.mbtiles

	echo combining:  done at $(date)

elif [[ $locationName == "cyclemap-large" ]]; then
	link $file data-tileserver/tiles-main.mbtiles
fi

./restart-tileserver.sh

