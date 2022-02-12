#!/bin/bash

egrep --text --no-filename '^quickstart: done at|^      : Git version|^Imposm took|Time: .*\([^()]*:[^()]*:[^()]*\)|^real' logs/update*.log

