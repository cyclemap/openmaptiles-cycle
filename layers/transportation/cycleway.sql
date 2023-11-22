
-- direction mapping type doesn't allow us to pass "unset"
CREATE OR REPLACE FUNCTION oneway(is_oneway INT, oneway_bicycle TEXT) RETURNS INT AS
$$
SELECT CASE
           WHEN oneway_bicycle = 'yes' THEN 1
           WHEN oneway_bicycle = 'no' THEN 0
           WHEN oneway_bicycle = '-1' THEN -1
           ELSE is_oneway
           END;
$$ LANGUAGE SQL IMMUTABLE
                STRICT
                PARALLEL SAFE;

CREATE OR REPLACE FUNCTION is_cycleway(highway TEXT, tags HSTORE) RETURNS boolean AS
$$
SELECT CASE
        WHEN highway IN ('construction') THEN false

        WHEN tags->'bicycle' IN ('no', 'private', 'permit') THEN false
        
		WHEN tags->'cycleway' IN ('separate') OR
            tags->'cycleway:left' IN ('separate') OR
            tags->'cycleway:right' IN ('separate') OR
            tags->'cycleway:both' IN ('separate') THEN false

        WHEN highway IN ('cycleway') THEN true
        
        WHEN tags->'mtb:scale' NOT IN ('6') OR
            tags->'mtb:scale:imba' IS NOT NULL OR
            tags->'mtb:type' IS NOT NULL OR
            tags->'bicycle' IN ('mtb') OR
            tags->'route' IN ('mtb') THEN true
        
        WHEN tags->'cycleway' IN ('lane', 'opposite_lane', 'opposite', 'share_busway', 'opposite_share_busway', 'shared', 'track', 'opposite_track') OR
            tags->'cycleway:left' IN ('lane', 'opposite_lane', 'opposite', 'share_busway', 'opposite_share_busway', 'shared', 'track', 'opposite_track') OR
            tags->'cycleway:right' IN ('lane', 'opposite_lane', 'opposite', 'share_busway', 'opposite_share_busway', 'shared', 'track', 'opposite_track') OR
            tags->'cycleway:both' IN ('lane', 'opposite_lane', 'opposite', 'share_busway', 'opposite_share_busway', 'shared', 'track', 'opposite_track') THEN true
        
        WHEN tags->'oneway' = 'yes' and tags->'oneway:bicycle' = 'no' THEN true
        
        WHEN highway IN ('pedestrian', 'living_street', 'path', 'footway', 'steps', 'bridleway', 'corridor', 'track') AND (
                tags->'bicycle' IN ('yes', 'permissive', 'dismount', 'designated') OR
                tags->'ramp:bicycle' NOT IN ('no') OR
                tags->'icn' = 'yes' OR tags->'icn_ref' IS NOT NULL OR
                tags->'ncn' = 'yes' OR tags->'ncn_ref' IS NOT NULL OR
                tags->'rcn' = 'yes' OR tags->'rcn_ref' IS NOT NULL OR
                tags->'lcn' = 'yes' OR tags->'lcn_ref' IS NOT NULL OR
                tags->'route' IN ('bicycle')
            )
            THEN true

        WHEN tags->'sport' ~ E'(;|^)cycling(;|$)' THEN true

        ELSE false
END;
$$ LANGUAGE SQL IMMUTABLE
                PARALLEL SAFE;

CREATE OR REPLACE FUNCTION is_max_speed_under(maxSpeed text, speedCutoff float, speedCutoffImperial float) RETURNS boolean AS
$$
SELECT CASE
        WHEN maxSpeed ~ E'^[\\d.]+$' AND maxSpeed::float <= speedCutoff THEN true
        WHEN maxSpeed ~ E'^[\\d.]+ km/h$' AND replace(maxSpeed, ' km/h', '')::float <= speedCutoff THEN true
        WHEN maxSpeed ~ E'^[\\d.]+ kph$' AND replace(maxSpeed, ' kph', '')::float <= speedCutoff THEN true
        WHEN maxSpeed ~ E'^[\\d.]+ mph$' AND replace(maxSpeed, ' mph', '')::float <= speedCutoffImperial THEN true
        ELSE false
END;
$$ LANGUAGE SQL IMMUTABLE
                PARALLEL SAFE;


CREATE OR REPLACE FUNCTION is_max_speed_low(tags HSTORE) RETURNS boolean AS
$$
SELECT is_max_speed_under(tags->'maxspeed', 60, 35);
$$ LANGUAGE SQL IMMUTABLE
                PARALLEL SAFE;

CREATE OR REPLACE FUNCTION is_max_speed_very_low(tags HSTORE) RETURNS boolean AS
$$
SELECT is_max_speed_under(tags->'maxspeed', 40, 25);
$$ LANGUAGE SQL IMMUTABLE
                PARALLEL SAFE;


CREATE OR REPLACE FUNCTION is_wide_or_unknown(tags HSTORE) RETURNS boolean AS
$$
SELECT CASE
        WHEN tags->'lanes' IS NULL OR tags->'lanes' !~ E'^[\\d]+$' THEN true
        WHEN (tags->'lanes')::integer > 2 OR (tags->'lanes')::integer < 1 THEN true
        WHEN tags->'oneway' = 'yes' AND (tags->'lanes')::integer != 1 THEN true
        
        -- 3.75m is 12.3 feet
        WHEN tags->'width' IS NOT NULL AND tags->'width' ~ E'^[\\d.]+$' AND (
            (tags->'lanes')::integer = 1 AND (tags->'width')::float < 3.75 OR
            (tags->'lanes')::integer = 2 AND (tags->'width')::float < 7.5
        ) THEN false
        WHEN tags->'width:carriageway' IS NOT NULL AND tags->'width:carriageway' ~ E'^[\\d.]+$' AND (
            (tags->'lanes')::integer = 1 AND (tags->'width:carriageway')::float < 3.75 OR
            (tags->'lanes')::integer = 2 AND (tags->'width:carriageway')::float < 7.5
        ) THEN false

        -- wide or unknown
        ELSE true
END;
$$ LANGUAGE SQL IMMUTABLE
                PARALLEL SAFE;


CREATE OR REPLACE FUNCTION is_cyclefriendly(highway TEXT, tags HSTORE) RETURNS boolean AS
$$
SELECT CASE
        WHEN highway IN ('construction') THEN false

        WHEN tags->'bicycle' IN ('no', 'private', 'permit') THEN false
        
        WHEN tags->'cycleway' IN ('separate') OR
            tags->'cycleway:left' IN ('separate') OR
            tags->'cycleway:right' IN ('separate') OR
            tags->'cycleway:both' IN ('separate') THEN false

        WHEN tags->'bicycle' IN ('designated') THEN true

        WHEN tags->'cycleway' IN ('shared_lane') OR
            tags->'cycleway:left' IN ('shared_lane') OR
            tags->'cycleway:right' IN ('shared_lane') OR
            tags->'cycleway:both' IN ('shared_lane') THEN true

        WHEN tags->'icn' = 'yes' OR tags->'icn_ref' IS NOT NULL OR
            tags->'ncn' = 'yes' OR tags->'ncn_ref' IS NOT NULL OR
            tags->'rcn' = 'yes' OR tags->'rcn_ref' IS NOT NULL OR
            tags->'lcn' = 'yes' OR tags->'lcn_ref' IS NOT NULL OR
            tags->'route' IN ('bicycle')
            THEN true
        
        WHEN tags->'bicycle' IN ('yes', 'permissive', 'dismount') AND (
                highway IN ('residential', 'service', 'unclassified') OR
                is_max_speed_low(tags) AND is_wide_or_unknown(tags) OR
                is_max_speed_very_low(tags)
            )
            THEN true
        
        ELSE false
END;
$$ LANGUAGE SQL IMMUTABLE
                PARALLEL SAFE;

-- Determine which transportation features are shown at all zoom levels

-- these are used to figure what the 50k cutoff should be by looking at the cutoff for ALL of the roads
-- zoom level, geometry distance cutoff (meters) from update_transportation_merge.sql:  anything smaller is filtered, the meters * 2**zoom (# = where we are checking this method)
-- 4   1000  16k   #
-- 5   500   16k   why the big jump?
-- 6   100   6k    #
-- 7   50    6k
-- 8   NA    NA    #

CREATE OR REPLACE FUNCTION transportation_filter_override(highway text, surface text, tags HSTORE, geometry_length float, zoom_level integer) RETURNS boolean AS
$$
SELECT CASE
           WHEN geometry_length > 50000/(1<<zoom_level) AND
               is_cycleway(highway, tags) THEN TRUE
           WHEN geometry_length > 50000/(1<<zoom_level) AND
               is_cyclefriendly(highway, tags) AND
               surface = 'unpaved' THEN TRUE
           ELSE FALSE
       END
$$ LANGUAGE SQL IMMUTABLE
                STRICT
                PARALLEL SAFE;

