EXECUTE IMMEDIATE FORMAT("""
    CREATE TABLE IF NOT EXISTS `%s` 
    OPTIONS (expiration_timestamp = TIMESTAMP_ADD(CURRENT_TIMESTAMP(), INTERVAL 30 DAY)) 
    AS
        SELECT 
            CAST(%s AS STRING) AS facility_id,
            CAST(%s AS STRING) AS customer_id,
            %s AS cost
        FROM `%s` 

""",
REPLACE(output_table, '`', ''),
facilities_column,
customers_column,
IF(
    transformation_bool,
    IF(
        UPPER(transformation_function) = 'POWER', 
        FORMAT('POW(%s, %d)', cost_column, CAST(transformation_parameter AS INT64)),
        IF(
            UPPER(transformation_function) = 'EXPONENTIAL',
            FORMAT('EXP(%d * %s)', CAST(transformation_parameter AS INT64), cost_column),
            FORMAT('%d * %s', CAST(transformation_parameter AS INT64), cost_column)
        )
    ),
    cost_column
),
REPLACE(costs_table, '`', '')
);

