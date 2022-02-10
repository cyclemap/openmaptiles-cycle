#!/bin/bash

set -e

git fetch --quiet https://github.com/openmaptiles/openmaptiles/

if [[ "$(git log --format=%H -1 FETCH_HEAD)" == "$(git merge-base FETCH_HEAD master)" ]]; then
	true
else
	echo UPDATE ME
fi

#there is no git rebase --dry-run

