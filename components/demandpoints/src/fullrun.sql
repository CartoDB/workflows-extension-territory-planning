DECLARE flag BOOL;
DECLARE query STRING;

BEGIN
    -- 1. Check unique dpoint_id
    SET query = FORMAT("""
        SELECT COUNT(DISTINCT %s) != COUNT(*)
        FROM `%s`
    """, dpoints_id, REPLACE(dpoints_table, '`', ''));
    EXECUTE IMMEDIATE query INTO flag;
    IF flag THEN
        RAISE USING MESSAGE = FORMAT('Demand points ID column `%s` must contain unique values.', dpoints_id);
    END IF;

    -- 2. Check valid geom    
    SET query = FORMAT("""
        SELECT COUNTIF(UPPER(ST_GEOMETRYTYPE(%s)) = 'ST_POINT') != COUNT(*)
        FROM `%s`
    """, dpoints_geom, REPLACE(dpoints_table, '`', ''));
    EXECUTE IMMEDIATE query INTO flag;
    IF flag THEN
        RAISE USING MESSAGE = FORMAT('Demand points Geometry column `%s` must contain point geometries.', dpoints_geom);
    END IF;

    -- 3. Check complete demand
    IF demand_bool THEN
        SET query = FORMAT("""
            SELECT COUNTIF(%s IS NOT NULL AND %s > 0) != COUNT(*)
            FROM `%s`
        """, demand_col, demand_col, REPLACE(dpoints_table, '`', ''));
        EXECUTE IMMEDIATE query INTO flag;
        IF flag THEN
            RAISE USING MESSAGE = FORMAT('Demand points demand column `%s` cannot contain NULL values and must be positive', demand_col);
        END IF;
    END IF;

    -- 4. Prepare dpoints data
    EXECUTE IMMEDIATE FORMAT("""
        CREATE TABLE IF NOT EXISTS `%s` 
        OPTIONS (expiration_timestamp = TIMESTAMP_ADD(CURRENT_TIMESTAMP(), INTERVAL 30 DAY)) 
        AS
            SELECT
                CAST(%s AS STRING) AS dpoint_id,
                %s AS geom,
                %s AS demand
            FROM `%s`
            ORDER BY dpoint_id
    """,
    REPLACE(output_table, '`', ''),
    dpoints_id,
    dpoints_geom,
    IF(demand_bool, demand_col, 'NULL'),
    REPLACE(dpoints_table, '`', '')
    );

END;