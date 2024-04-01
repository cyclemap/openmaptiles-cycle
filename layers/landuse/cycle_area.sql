
-- this override is additive.

CREATE OR REPLACE FUNCTION landuse_filter_override(class text, zoom_level integer) RETURNS boolean AS
$$
SELECT CASE
    WHEN subclass IN ('cycling')
        THEN TRUE
    ELSE FALSE
END
$$ LANGUAGE SQL IMMUTABLE
                STRICT
                PARALLEL SAFE;

