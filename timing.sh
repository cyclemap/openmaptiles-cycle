#!/bin/bash

#egrep --text --no-filename '^quickstart: done at|^      : Git version|^Imposm took|Time: .*\([^()]*:[^()]*:[^()]*\)|^real' logs/update*.log |
#	sed --regexp-extended -e 's/Time:.*\((.*)\..*\)/\1/' -e 's/.*Git version.*: (.*)/\1/' |
#	sed --regexp-extended ':a;N;$!ba;s/\n/ /g;s/quickstart: done at .{32}/&\n/g;'


egrep --text --no-filename '^Time:.* d |^==========|^quickstart|NOTICE:  (aggregate highest_highway|Finished layer poi)' logs/update*.log |
	uniq

