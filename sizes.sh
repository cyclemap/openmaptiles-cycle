#!/bin/bash

##DOESN'T WORK
#python3 <<<'
#import math
#def num2deg(xtile, ytile, zoom):
#	n = 2.0 ** zoom
#	lon_deg = xtile / n * 360.0 - 180.0
#	lat_rad = math.atan(math.sinh(math.pi * (1 - 2 * ytile / n)))
#	lat_deg = math.degrees(lat_rad)
#	return (lat_deg, lon_deg)
#
#print(num2deg(2503,9367,13))
#print(num2deg(5188,10757,13))
#'

##DOESN'T WORK
#python3 <<<'
#import math
#def deg2num(lat_deg, lon_deg, zoom):
#	lat_rad = math.radians(lat_deg)
#	n = 2.0 ** zoom
#	xtile = int((lon_deg + 180.0) / 360.0 * n)
#	ytile = int((1.0 - math.asinh(math.tan(lat_rad)) / math.pi) / 2.0 * n)
#	return (xtile, ytile)
#
#print(deg2num(25, -125, 14))
#print(deg2num(49, -66, 14))
#'

function runAll() {
	sqls="$@"
	for file in data-tileserver/bak/*.mbtiles data-tileserver/*.mbtiles; do
		echo "$file $(
			for sql in "${sqls[@]}"; do
				sqlite3 $file "$sql"
			done
		)"
	done
}


#sqlite3 tiles-2022-11-11-cyclemaps-small-14.mbtiles 'select min(tile_row),max(tile_row),min(tile_column),max(tile_column) from map where zoom_level=5 limit 10;' >>sizes.sh
#19|19|9|9
row=19
column=9
rowMin=$(($row-0))
rowMax=$(($row+0))
columnMin=$(($column-0))
columnMax=$(($column+0))
tileFilter5="zoom_level=5 and $columnMin <= tile_column and tile_column <= $columnMax and $rowMin <= tile_row and tile_row <= $rowMax"

#10093|10151|4655|4701
row=10115
column=4675
rowMin=$(($row-20))
rowMax=$(($row+20))
columnMin=$(($column-20))
columnMax=$(($column+20))
tileFilter14="zoom_level=14 and $columnMin <= tile_column and tile_column <= $columnMax and $rowMin <= tile_row and tile_row <= $rowMax"

select='select count(map.tile_id), round(avg(length(tile_data))) from map JOIN images ON images.tile_id = map.tile_id where';
runAll "$select $tileFilter14;" "$select $tileFilter5;"


