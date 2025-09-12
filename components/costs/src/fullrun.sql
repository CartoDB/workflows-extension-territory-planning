DECLARE flag BOOL;
DECLARE query STRING;
DECLARE create_output_query STRING;

BEGIN

    SET output_table = REPLACE(output_table, '`', '');

    -- Set variables based on whether the workflow is executed via API
    IF REGEXP_CONTAINS(output_table, r'^[^.]+\.[^.]+\.[^.]+$') THEN
        SET create_output_query = FORMAT('CREATE TABLE IF NOT EXISTS `%s` OPTIONS (expiration_timestamp = TIMESTAMP_ADD(CURRENT_TIMESTAMP(), INTERVAL 30 DAY))', output_table);
    ELSE
        -- Output needs to be qualified with tempStoragePath, meaning an API execution of the Workflow
        SET create_output_query = FORMAT('CREATE TEMPORARY TABLE `%s`', output_table);
    END IF;

    -- 1. Check input data
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
    dpoints_column,
    REPLACE(costs_table, '`', ''));
    EXECUTE IMMEDIATE query INTO flag;
    IF flag THEN
        RAISE USING MESSAGE = 'Found multiple cost values for facility-client pair(s). Please assign one cost value per facility-customer pair.';
    END IF;

    -- 2. Prepare costs
    EXECUTE IMMEDIATE FORMAT("""
        %s
        AS
            SELECT 
                CAST(%s AS STRING) AS facility_id,
                CAST(%s AS STRING) AS dpoint_id,
                %s AS cost
            FROM `%s` 
            ORDER BY facility_id, dpoint_id

    """,
    create_output_query,
    facilities_column,
    dpoints_column,
    IF(
        transformation_bool,
        IF(
            UPPER(transformation_function) = 'POWER', 
            FORMAT('POW(%s, %f)', cost_column, transformation_parameter),
            FORMAT('EXP(%f * %s)', transformation_parameter, cost_column)
        ),
        cost_column
    ),
    REPLACE(costs_table, '`', '')
    );

END;