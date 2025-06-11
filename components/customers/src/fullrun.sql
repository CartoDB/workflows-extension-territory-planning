EXECUTE IMMEDIATE FORMAT("""
    CREATE TABLE IF NOT EXISTS `%s` 
    OPTIONS (expiration_timestamp = TIMESTAMP_ADD(CURRENT_TIMESTAMP(), INTERVAL 30 DAY)) 
    AS
        SELECT 
            CAST(%s AS STRING) AS customer_id,
            %s AS geom,
            %s AS demand
        FROM `%s` 

""",
REPLACE(output_table, '`', ''),
customers_id,
customers_geom,
IF(demand_bool, demand_col, 'NULL'),
REPLACE(customers_table, '`', '')
);