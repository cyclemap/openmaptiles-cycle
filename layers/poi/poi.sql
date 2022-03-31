-- etldoc: layer_poi[shape=record fillcolor=lightpink, style="rounded,filled",
-- etldoc:     label="layer_poi | <z12> z12 | <z13> z13 | <z14_> z14+" ] ;

CREATE OR REPLACE FUNCTION layer_poi(bbox geometry, zoom_level integer, pixel_width numeric)
    RETURNS TABLE
            (
                osm_id   bigint,
                geometry geometry,
                name     text,
                name_en  text,
                name_de  text,
                tags     hstore,
                class    text,
                subclass text,
                agg_stop integer,
                layer    integer,
                level    integer,
                indoor   integer,
                drinking_water_seasonal integer,
                "rank"   int
            )
AS
$$
SELECT osm_id_hash AS osm_id,
       geometry,
       NULLIF(name, '') AS name,
       COALESCE(NULLIF(name_en, ''), name) AS name_en,
       COALESCE(NULLIF(name_de, ''), name, name_en) AS name_de,
       tags,
       poi_class(subclass, mapping_key) AS class,
       CASE
           WHEN subclass = 'information'
               THEN NULLIF(information, '')
           WHEN subclass = 'place_of_worship'
               THEN NULLIF(religion, '')
           WHEN subclass = 'pitch'
               THEN NULLIF(sport, '')
           ELSE subclass
           END AS subclass,
       agg_stop,
       NULLIF(layer, 0) AS layer,
       "level",
       CASE WHEN indoor = TRUE THEN 1 END AS indoor,
       CASE
           WHEN drinking_water_seasonal = 'yes' THEN 1
           WHEN (
               drinking_water_seasonal = 'no' OR
               subclass = 'drinking_water' AND indoor = TRUE
           ) THEN 0
           END AS drinking_water_seasonal,
       row_number() OVER (
           PARTITION BY LabelGrid(geometry, 50 * pixel_width)
           ORDER BY CASE WHEN name = '' THEN 2000 ELSE poi_class_rank(poi_class(subclass, mapping_key)) END ASC
           )::int AS "rank"
FROM (
         -- etldoc: osm_poi_point ->  layer_poi:z12
         -- etldoc: osm_poi_point ->  layer_poi:z13
         SELECT *,
                osm_id * 10 AS osm_id_hash
         FROM osm_poi_point
         WHERE geometry && bbox
           AND zoom_level BETWEEN 12 AND 13
           AND subclass IN ('park', 'nature_reserve', 'bicycle', 'bicycle_rental', 'bicycle_repair_station')

         UNION ALL

         -- etldoc: osm_poi_point ->  layer_poi:z14_
         SELECT *,
                osm_id * 10 AS osm_id_hash
         FROM osm_poi_point
         WHERE geometry && bbox
           AND zoom_level >= 14
           AND subclass IN ('park', 'nature_reserve', 'bicycle', 'bicycle_rental', 'bicycle_repair_station', 'bicycle_parking', 'drinking_water', 'toilets', 'ford', 'compressed_air', 'shelter')

         UNION ALL

         -- etldoc: osm_poi_polygon ->  layer_poi:z12
         -- etldoc: osm_poi_polygon ->  layer_poi:z13
         SELECT *,
                NULL::integer AS agg_stop,
                CASE
                    WHEN osm_id < 0 THEN -osm_id * 10 + 4
                    ELSE osm_id * 10 + 1
                    END AS osm_id_hash
         FROM osm_poi_polygon
         WHERE geometry && bbox
           AND zoom_level BETWEEN 12 AND 13
           AND subclass IN ('park', 'nature_reserve', 'bicycle', 'bicycle_rental', 'bicycle_repair_station')

         UNION ALL

         -- etldoc: osm_poi_polygon ->  layer_poi:z14_
         SELECT *,
                NULL::integer AS agg_stop,
                CASE
                    WHEN osm_id < 0 THEN -osm_id * 10 + 4
                    ELSE osm_id * 10 + 1
                    END AS osm_id_hash
         FROM osm_poi_polygon
         WHERE geometry && bbox
           AND zoom_level >= 14
           AND subclass IN ('park', 'nature_reserve', 'bicycle', 'bicycle_rental', 'bicycle_repair_station', 'bicycle_parking', 'drinking_water', 'toilets', 'ford', 'compressed_air', 'shelter')
     ) AS poi_union
ORDER BY "rank"
$$ LANGUAGE SQL STABLE
                PARALLEL SAFE;
-- TODO: Check if the above can be made STRICT -- i.e. if pixel_width could be NULL
