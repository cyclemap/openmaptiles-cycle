#!/bin/bash

function printLog() {
	time=$1; shift
	difference=$1; shift
	echo "$(date --iso-8601 --date="@$time") $(($difference/3600)) $@"
}

last=$(date +%s)
time=$last
<logs/update.log \
	egrep --text --no-filename 'Generating zoom .*\.\.\.$|Tile generation complete!$|^(updating|quickstart|generating tiles|combining): (done|started) at|^real	' |
	tail -n100 |
	while read line; do
		<<<$line egrep --text -q 'Generating zoom .*\.\.\.$|Tile generation complete!$' && {
			time=$(<<<$line cut -b1-19 |sed --regexp-extended 's/ (.{2})-(.{2})-(.{2})/ \1:\2:\3/')
			comment=$(<<<$line cut -b21-)
			#different timezone.  fun
			time=$(date +%s --utc --date="$time")
			difference=$(($time-$last))
			last=$time
			<<<$line egrep -q 'Tile generation complete!$' && {
				comment="$lastComment $comment"
			} || {
				lastComment=$comment
				comment='finished importing'
			}
			
			printLog $time $difference $comment
		}
		<<<$line egrep -q '^(updating|quickstart|generating tiles|combining): (done|started) at' && {
			comment=$(<<<$line sed 's/at .*//')
			time=$(<<<$line sed 's/.* at //')
			time=$(date +%s --date="$time")
			difference=$(($time-$last))
			last=$time
			
			<<<$line egrep -q '^updating: started at' && echo
			<<<$line egrep -q '^combining: done at' && printLog $time $difference combining
		}
		<<<$line egrep -q '^real	' && {
			difference=$(($(<<<$line sed 's/real	\(.*\)m.*/\1/')*60))
			printLog $time $difference "main total"
		}
	done

