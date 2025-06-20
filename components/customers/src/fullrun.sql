DECLARE flag BOOL;
DECLARE query STRING;

BEGIN
    -- 1. Check unique customer_id
    SET query = FORMAT("""
        SELECT COUNT(DISTINCT %s) != COUNT(*)
        FROM `%s`
    """, customers_id, REPLACE(customers_table, '`', ''));
    EXECUTE IMMEDIATE query INTO flag;
    IF flag THEN
        RAISE USING MESSAGE = FORMAT('Customers ID column `%s` must contain unique values.', customers_id);
    END IF;

    -- 2. Check valid geom    
    SET query = FORMAT("""
        SELECT COUNTIF(UPPER(ST_GEOMETRYTYPE(%s)) = 'ST_POINT') != COUNT(*)
        FROM `%s`
    """, customers_geom, REPLACE(customers_table, '`', ''));
    EXECUTE IMMEDIATE query INTO flag;
    IF flag THEN
        RAISE USING MESSAGE = FORMAT('Customers Geometry column `%s` must contain point geometries.', customers_geom);
    END IF;

    -- 3. Check complete demand
    IF demand_bool THEN
        SET query = FORMAT("""
            SELECT COUNTIF(%s IS NOT NULL) != COUNT(*)
            FROM `%s`
        """, demand_col, REPLACE(customers_table, '`', ''));
        EXECUTE IMMEDIATE query INTO flag;
        IF flag THEN
            RAISE USING MESSAGE = FORMAT('Customers demand column `%s` cannot contain NULL values.', demand_col);
        END IF;
    END IF;

    -- 4. Prepare customers data
    EXECUTE IMMEDIATE FORMAT("""
        CREATE TABLE IF NOT EXISTS `%s` 
        OPTIONS (expiration_timestamp = TIMESTAMP_ADD(CURRENT_TIMESTAMP(), INTERVAL 30 DAY)) 
        AS
            SELECT
                CAST(%s AS STRING) AS customer_id,
                %s AS geom,
                %s AS demand
            FROM `%s`
            ORDER BY customer_id
    """,
    REPLACE(output_table, '`', ''),
    customers_id,
    customers_geom,
    IF(demand_bool, demand_col, 'NULL'),
    REPLACE(customers_table, '`', '')
    );

END;