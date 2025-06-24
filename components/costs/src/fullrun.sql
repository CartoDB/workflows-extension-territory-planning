DECLARE query STRING;
DECLARE flag BOOL;

BEGIN

    SET query = FORMAT("""
        SELECT COUNTIF(%s IS NOT NULL AND %s >= 0) != COUNT(*)
        FROM `%s`
    """, 
    cost_column,
    cost_column,
    REPLACE(costs_table, '`', ''));
    EXECUTE IMMEDIATE query INTO flag;
    IF flag THEN
        RAISE USING MESSAGE = 'All costs must be non-negative and cannot have NULL values.';
    END IF;

    SET query = FORMAT("""
        SELECT COUNT(*) != COUNT(DISTINCT CONCAT(CAST(%s AS STRING), '-', CAST(%s AS STRING))) 
        FROM `%s`
    """, 
    facilities_column,
    customers_column,
    REPLACE(costs_table, '`', ''));
    EXECUTE IMMEDIATE query INTO flag;
    IF flag THEN
        RAISE USING MESSAGE = 'Found multiple cost values for facility-client pair(s). Please assign one cost value per facility-customer pair.';
    END IF;

    EXECUTE IMMEDIATE FORMAT("""
        CREATE TABLE IF NOT EXISTS `%s` 
        OPTIONS (expiration_timestamp = TIMESTAMP_ADD(CURRENT_TIMESTAMP(), INTERVAL 30 DAY)) 
        AS
            SELECT 
                CAST(%s AS STRING) AS facility_id,
                CAST(%s AS STRING) AS customer_id,
                %s AS cost
            FROM `%s` 
            ORDER BY facility_id, customer_id

    """,
    REPLACE(output_table, '`', ''),
    facilities_column,
    customers_column,
    IF(
        transformation_bool,
        IF(
            UPPER(transformation_function) = 'POWER', 
            FORMAT('POW(%s, %f)', cost_column, transformation_parameter),
            IF(
                UPPER(transformation_function) = 'EXPONENTIAL',
                FORMAT('EXP(%f * %s)', transformation_parameter, cost_column),
                FORMAT('%f * %s', transformation_parameter, cost_column)
            )
        ),
        cost_column
    ),
    REPLACE(costs_table, '`', '')
    );

END;