CREATE OR REPLACE FUNCTION brunnel(is_bridge bool, is_tunnel bool, is_ford bool) RETURNS text AS
$$
SELECT CASE
           WHEN is_bridge THEN 'bridge'
           WHEN is_tunnel THEN 'tunnel'
           WHEN is_ford THEN 'ford'
           END;
$$ LANGUAGE SQL IMMUTABLE
                STRICT
                PARALLEL SAFE;

CREATE OR REPLACE FUNCTION is_cycleway(highway TEXT, tags HSTORE = null) RETURNS boolean AS
$$
SELECT CASE
        WHEN tags->'bicycle' IN ('no', 'private', 'permit') THEN false

        WHEN tags->'mtb:scale' NOT IN ('6') OR
            tags->'mtb:scale:imba' IS NOT NULL OR
            tags->'mtb:type' IS NOT NULL OR
            tags->'bicycle' IN ('mtb') THEN true
        
        WHEN tags->'cycleway' IN ('lane', 'opposite_lane', 'opposite', 'share_busway', 'shared', 'track', 'opposite_track') OR
            tags->'cycleway:left' IN ('lane', 'opposite_lane', 'opposite', 'share_busway', 'shared', 'track', 'opposite_track') OR
            tags->'cycleway:right' IN ('lane', 'opposite_lane', 'opposite', 'share_busway', 'shared', 'track', 'opposite_track') OR
            tags->'cycleway:both' IN ('lane', 'opposite_lane', 'opposite', 'share_busway', 'shared', 'track', 'opposite_track') THEN true
        
        WHEN highway IN ('cycleway') THEN true
        
        WHEN highway IN ('pedestrian', 'living_street', 'path', 'footway', 'steps', 'bridleway', 'corridor', 'track') AND
            (tags->'bicycle' IN ('yes', 'permissive', 'dismount', 'designated') OR
            tags->'icn' = 'yes' OR tags->'icn_ref' IS NOT NULL OR
            tags->'ncn' = 'yes' OR tags->'ncn_ref' IS NOT NULL OR
            tags->'rcn' = 'yes' OR tags->'rcn_ref' IS NOT NULL OR
            tags->'lcn' = 'yes' OR tags->'lcn_ref' IS NOT NULL)
            THEN true

        ELSE false
END;
$$ LANGUAGE SQL IMMUTABLE
                PARALLEL SAFE;


CREATE OR REPLACE FUNCTION is_cyclefriendly(highway TEXT, tags HSTORE = null) RETURNS boolean AS
$$
SELECT CASE
        WHEN tags->'bicycle' IN ('no', 'private', 'permit') THEN false

        WHEN tags->'bicycle' IN ('designated') OR
            tags->'cycleway' IN ('shared_lane') OR
            tags->'cycleway:left' IN ('shared_lane') OR
            tags->'cycleway:right' IN ('shared_lane') OR
            tags->'cycleway:both' IN ('shared_lane') THEN true

        WHEN tags->'bicycle' IN ('yes', 'permissive', 'dismount') AND (
            highway IN ('residential', 'service', 'unclassified') OR
            (tags->'maxspeed' ~ E'^\\d+ mph$' AND replace(tags->'maxspeed', ' mph', '')::integer <= 35) OR
            (tags->'maxspeed' ~ E'^\\d+ kph$' AND replace(tags->'maxspeed', ' kph', '')::integer <= 60)
            ) THEN true
        
        WHEN tags->'icn' = 'yes' OR tags->'icn_ref' IS NOT NULL OR
            tags->'ncn' = 'yes' OR tags->'ncn_ref' IS NOT NULL OR
            tags->'rcn' = 'yes' OR tags->'rcn_ref' IS NOT NULL OR
            tags->'lcn' = 'yes' OR tags->'lcn_ref' IS NOT NULL
            THEN true
        
        ELSE false
END;
$$ LANGUAGE SQL IMMUTABLE
                PARALLEL SAFE;



-- The classes for highways are derived from the classes used in ClearTables
-- https://github.com/ClearTables/ClearTables/blob/master/transportation.lua
CREATE OR REPLACE FUNCTION highway_class(highway TEXT, public_transport TEXT, construction TEXT, tags HSTORE = null) RETURNS TEXT AS
$$
SELECT CASE
        WHEN is_cycleway(highway, tags) THEN 'cycleway'
        WHEN is_cyclefriendly(highway, tags) THEN 'cyclefriendly'

        WHEN highway IN ('service', 'track') THEN highway
        WHEN highway IN ('motorway', 'motorway_link') THEN 'motorway'
        WHEN highway IN ('trunk', 'trunk_link') THEN 'trunk'
        WHEN highway IN ('primary', 'primary_link') THEN 'primary'
        WHEN highway IN ('secondary', 'secondary_link') THEN 'secondary'
        WHEN highway IN ('tertiary', 'tertiary_link') THEN 'tertiary'
        WHEN highway IN ('unclassified', 'residential', 'living_street', 'road') THEN 'minor'
        WHEN highway IN ('pedestrian', 'path', 'footway', 'steps', 'bridleway', 'corridor') OR public_transport IN ('platform') THEN 'path'
        WHEN highway = 'raceway' THEN 'raceway'
        WHEN highway = 'construction' THEN CASE
          WHEN construction IN ('motorway', 'motorway_link') THEN 'motorway_construction'
          WHEN construction IN ('trunk', 'trunk_link') THEN 'trunk_construction'
          WHEN construction IN ('primary', 'primary_link') THEN 'primary_construction'
          WHEN construction IN ('secondary', 'secondary_link') THEN 'secondary_construction'
          WHEN construction IN ('tertiary', 'tertiary_link') THEN 'tertiary_construction'
          WHEN construction IS NULL OR construction IN ('unclassified', 'residential', 'living_street', 'road') THEN 'minor_construction'
          WHEN construction IN ('pedestrian', 'path', 'footway', 'cycleway', 'steps', 'bridleway', 'corridor') OR public_transport IN ('platform') THEN 'path_construction'
          WHEN construction IN ('service', 'track', 'raceway') THEN CONCAT(highway, '_construction')
          ELSE NULL
        END
        ELSE NULL
END;
$$ LANGUAGE SQL IMMUTABLE
                PARALLEL SAFE;

-- The classes for railways are derived from the classes used in ClearTables
-- https://github.com/ClearTables/ClearTables/blob/master/transportation.lua
CREATE OR REPLACE FUNCTION railway_class(railway text) RETURNS text AS
$$
SELECT CASE
           WHEN railway IN ('rail', 'narrow_gauge', 'preserved', 'funicular') THEN 'rail'
           WHEN railway IN ('subway', 'light_rail', 'monorail', 'tram') THEN 'transit'
           END;
$$ LANGUAGE SQL IMMUTABLE
                STRICT
                PARALLEL SAFE;

-- Limit service to only the most important values to ensure
-- we always know the values of service
CREATE OR REPLACE FUNCTION service_value(service text) RETURNS text AS
$$
SELECT CASE
           WHEN service IN ('spur', 'yard', 'siding', 'crossover', 'driveway', 'alley', 'parking_aisle') THEN service
           END;
$$ LANGUAGE SQL IMMUTABLE
                STRICT
                PARALLEL SAFE;

-- Limit surface to only the most important values to ensure
-- we always know the values of surface
CREATE OR REPLACE FUNCTION surface_value(surface text, highway TEXT, tags HSTORE = null) RETURNS text AS
$$
SELECT CASE
           WHEN surface ~ E'(;|^)(unpaved|artificial_turf|clay|compacted|crushed_limestone|dirt|earth|fine_gravel|grass|grass_paver|gravel|gravel_turf|ground|ice|mud|pebblestone|rock|rocky|salt|sand|snow|soil|stone|woodchips)(;|$)' THEN 'unpaved'
           WHEN surface ~ E'(;|^)paved|acrylic|asphalt|brick|bricks|cement|chipseal|cobblestone|concrete|granite|interlock|metal|paving_stones|sett|tartan|unhewn_cobblestone|wood(;|$)' THEN 'paved'
           WHEN tags->'footway' IN ('crossing') THEN 'paved'
           WHEN tags->'bicycle' IN ('mtb') THEN 'unpaved'
           WHEN tags->'mtb:scale' IS NOT NULL THEN 'unpaved'
           WHEN tags->'mtb:scale:imba' IS NOT NULL THEN 'unpaved'
           WHEN tags->'mtb:type' IS NOT NULL THEN 'unpaved'
           WHEN highway IN ('motorway', 'trunk', 'primary', 'secondary', 'tertiary', 'unclassified', 'residential', 'living_street', 'road', 'service', 'motorway_link', 'trunk_link', 'primary_link', 'secondary_link', 'tertiary_link', 'raceway', 'steps', 'cycleway') THEN 'paved'
           WHEN highway IN ('track') THEN 'unpaved'
           WHEN tags->'hiking' IN ('yes', 'designated', 'permissive') THEN 'unpaved'
           ELSE NULL
           END;
$$ LANGUAGE SQL IMMUTABLE
                STRICT
                PARALLEL SAFE;
