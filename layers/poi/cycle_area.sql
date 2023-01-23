
-- this override is restrictive at 12 to 13 and additive at 14 and above.

CREATE OR REPLACE FUNCTION poi_filter_override(subclass text, zoom_level integer) RETURNS boolean AS
$$
SELECT CASE
    WHEN zoom_level BETWEEN 12 AND 13
        AND subclass IN ('park', 'nature_reserve', 'camp_site', 'bicycle', 'bicycle_rental', 'bicycle_repair_station')
        THEN TRUE
    WHEN zoom_level >= 14 AND
        subclass IN ('park', 'nature_reserve', 'camp_site', 'bicycle', 'bicycle_rental', 'bicycle_repair_station', 'bicycle_parking', 'drinking_water', 'toilets', 'ford', 'compressed_air', 'shelter')
        THEN TRUE
    ELSE FALSE
END
$$ LANGUAGE SQL IMMUTABLE
                STRICT
                PARALLEL SAFE;

