#!/bin/bash

#egrep --text --no-filename '^quickstart: done at|^      : Git version|^Imposm took|Time: .*\([^()]*:[^()]*:[^()]*\)|^real' logs/update*.log |
#	sed --regexp-extended -e 's/Time:.*\((.*)\..*\)/\1/' -e 's/.*Git version.*: (.*)/\1/' |
#	sed --regexp-extended ':a;N;$!ba;s/\n/ /g;s/quickstart: done at .{32}/&\n/g;'

#egrep --text --no-filename '^Time:.*( d |\(.*:.*:.*\))|Generating zoom .*\.\.\.$|Tile generation complete!$|^(updating|quickstart): (done|started) at' logs/update*.log


last=$(date +%s)
<logs/update.log \
	egrep --text --no-filename 'Generating zoom .*\.\.\.$|Tile generation complete!$|^(updating|quickstart): (done|started) at' |
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
			
			echo "$(($difference/3600)) $comment"
		}
		<<<$line egrep -q '^(updating|quickstart): (done|started) at' && {
			time=$(<<<$line sed 's/.* at //')
			time=$(date +%s --date="$time")
			last=$time
			
			<<<$line egrep -q '^updating: started at' && echo
		}
done

