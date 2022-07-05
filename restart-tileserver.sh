#!/bin/bash

set -e #exit on failure

docker rm -f tileserver-gl || true

make start-tileserver #this does the copy

sleep 2

echo ready
