#!/bin/bash

set -e #exit on failure

docker restart tileserver-gl

sleep 2

echo ready
