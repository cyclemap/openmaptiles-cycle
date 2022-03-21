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

-- The classes for highways are derived from the classes used in ClearTables
-- https://github.com/ClearTables/ClearTables/blob/master/transportation.lua
CREATE OR REPLACE FUNCTION highway_class(highway TEXT, public_transport TEXT, construction TEXT, tags HSTORE = null) RETURNS TEXT AS
$$
SELECT CASE
           WHEN is_cycleway(highway, tags) THEN 'cycleway'
           WHEN is_cyclefriendly(highway, tags) THEN 'cyclefriendly'

           %%FIELD_MAPPING: class %%
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
           WHEN surface ~ E'(;|:|^)(unpaved|artificial_turf|clay|compacted|crushed_limestone|dirt|dirt/sand|earth|fine_gravel|grass|grass_paver|gravel|gravel_turf|ground|ice|mud|pebblestone|rock|rocky|salt|sand|shells|snow|soil|stone|woodchips)(;|:|$)' THEN 'unpaved'
           WHEN surface ~ E'(;|:|^)(paved|acrylic|asphalt|brick|bricks|cement|chipseal|cobblestone|concrete|granite|interlock|metal|metal_grid|paving_stones|plastic|rubber|sett|tartan|unhewn_cobblestone|wood)(;|:|$)' THEN 'paved'
           WHEN tags->'footway' IN ('crossing', 'access_aisle') THEN 'paved'
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

-- Determine which transportation features are shown at zoom 12
CREATE OR REPLACE FUNCTION transportation_filter_z12(highway text, construction text, surface text, tags HSTORE) RETURNS boolean AS
$$
SELECT CASE
           WHEN is_cycleway(highway, tags) THEN TRUE
           WHEN is_cyclefriendly(highway, tags) THEN TRUE
           WHEN surface_value(surface, highway, tags) = 'unpaved' THEN TRUE
           WHEN highway IN ('unclassified', 'residential') THEN TRUE
           WHEN highway_class(highway, '', construction) IN
               (
                'motorway', 'trunk', 'primary', 'secondary', 'tertiary', 'raceway',
                'motorway_construction', 'trunk_construction', 'primary_construction',
                'secondary_construction', 'tertiary_construction', 'raceway_construction',
                'busway'
               ) THEN TRUE --includes ramps
           ELSE FALSE
       END
$$ LANGUAGE SQL IMMUTABLE
                STRICT
                PARALLEL SAFE;

-- Determine which transportation features are shown at zoom 13
-- Assumes that piers have already been excluded
CREATE OR REPLACE FUNCTION transportation_filter_z13(highway text,
                                                     public_transport text,
                                                     construction text,
                                                     service text,
                                                     surface text,
                                                     tags HSTORE) RETURNS boolean AS
$$
SELECT CASE
           WHEN transportation_filter_z12(highway, construction, surface, tags) THEN TRUE
           WHEN highway = 'service' OR construction = 'service' THEN service NOT IN ('driveway', 'parking_aisle')
           WHEN highway_class(highway, public_transport, construction) IN ('minor', 'minor_construction') THEN TRUE
           ELSE FALSE
       END
$$ LANGUAGE SQL IMMUTABLE
                STRICT
                PARALLEL SAFE;
