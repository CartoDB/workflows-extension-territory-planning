DECLARE candidates_query STRING DEFAULT '';
DECLARE required_query STRING DEFAULT '';
DECLARE competitors_query STRING DEFAULT '';
DECLARE query STRING;
DECLARE flag BOOL;
DECLARE create_output_query STRING;

BEGIN
BEGIN

    SET output_table = REPLACE(output_table, '`', '');
    SET candidates_table = REPLACE(candidates_table, '`', '');
    SET required_table = REPLACE(required_table, '`', '');
    SET competitors_table = REPLACE(competitors_table, '`', '');

    -- Set variables based on whether the workflow is executed via API
    IF REGEXP_CONTAINS(output_table, r'^[^.]+\.[^.]+\.[^.]+$') THEN
        SET create_output_query = FORMAT('CREATE TABLE IF NOT EXISTS `%s` OPTIONS (expiration_timestamp = TIMESTAMP_ADD(CURRENT_TIMESTAMP(), INTERVAL 30 DAY))', output_table);
    ELSE
        -- Output needs to be qualified with tempStoragePath, meaning an API execution of the Workflow
        SET create_output_query = FORMAT('CREATE TEMPORARY TABLE `%s`', output_table);
    END IF;

    -- 1. Check NULLs
    SET query = FORMAT("""
        SELECT COUNTIF(%s %s %s %s %s %s) != COUNT(*)
        FROM `%s`
    """, 
    FORMAT("%s IS NOT NULL", candidates_id),
    FORMAT("AND %s IS NOT NULL", candidates_geom),
    IF(group_bool, FORMAT("AND %s IS NOT NULL", candidates_group), ''),
    IF(min_usage_bool, FORMAT("AND %s IS NOT NULL", candidates_min_usage), ''),
    IF(max_capacity_bool, FORMAT("AND %s IS NOT NULL", candidates_max_capacity), ''),
    IF(costofopen_bool, FORMAT("AND %s IS NOT NULL", candidates_costofopen), ''),
    candidates_table
    );
    EXECUTE IMMEDIATE query INTO flag;
    IF flag THEN
        RAISE USING MESSAGE = 'Candidate facilities data contains NULLs in selected features';
    END IF;

    IF required_bool THEN
        SET query = FORMAT("""
            SELECT COUNTIF(%s %s %s %s %s %s) != COUNT(*)
            FROM `%s`
        """, 
        FORMAT("%s IS NOT NULL", required_id),
        FORMAT("AND %s IS NOT NULL", required_geom),
        IF(group_bool, FORMAT("AND %s IS NOT NULL", required_group), ''),
        IF(min_usage_bool, FORMAT("AND %s IS NOT NULL", required_min_usage), ''),
        IF(max_capacity_bool, FORMAT("AND %s IS NOT NULL", required_max_capacity), ''),
        IF(costofopen_bool, FORMAT("AND %s IS NOT NULL", required_costofopen), ''),
        required_table
        );
        EXECUTE IMMEDIATE query INTO flag;
        IF flag THEN
            RAISE USING MESSAGE = 'Required facilities data contains NULLs in selected features';
        END IF;
    END IF;

    IF competitors_bool THEN
        SET query = FORMAT("""
            SELECT COUNTIF(%s %s) != COUNT(*)
            FROM `%s`
        """, 
        FORMAT("%s IS NOT NULL", competitors_id),
        FORMAT("AND %s IS NOT NULL", competitors_geom),
        competitors_table
        );
        EXECUTE IMMEDIATE query INTO flag;
        IF flag THEN
            RAISE USING MESSAGE = 'Competitor facilities data contains NULLs in selected features';
        END IF;
    END IF;

    -- 2. Prepare data
    SET candidates_query = FORMAT("""
        SELECT 
            CAST(%s AS STRING) AS facility_id,
            %s AS geom,
            0 AS facility_type,
            CAST(%s AS STRING) AS group_id,
            %s AS min_usage,
            %s AS max_capacity,
            %s AS cost_of_open
        FROM `%s` 
    """,
    candidates_id,
    candidates_geom,
    IF(group_bool, candidates_group, 'NULL'),
    IF(min_usage_bool, candidates_min_usage, 'NULL'),
    IF(max_capacity_bool, candidates_max_capacity, 'NULL'),
    IF(costofopen_bool, candidates_costofopen, 'NULL'),
    candidates_table
    );

    IF required_bool THEN
        SET required_query = FORMAT("""
            UNION ALL
            SELECT 
                CAST(%s AS STRING) AS facility_id,
                %s AS geom,
                1 AS facility_type,
                CAST(%s AS STRING) AS group_id,
                %s AS min_usage,
                %s AS max_capacity,
                %s AS cost_of_open
            FROM `%s` 
        """,
        required_id,
        required_geom,
        IF(group_bool, required_group, 'NULL'),
        IF(min_usage_bool, required_min_usage, 'NULL'),
        IF(max_capacity_bool, required_max_capacity, 'NULL'),
        IF(costofopen_bool, required_costofopen, 'NULL'),
        required_table
        );
    END IF;

    IF competitors_bool THEN
        SET competitors_query = FORMAT("""
            UNION ALL
            SELECT 
                CAST(%s AS STRING) AS facility_id,
                %s AS geom,
                2 AS facility_type,
                NULL AS group_id,
                NULL AS min_usage,
                NULL AS max_capacity,
                NULL AS cost_of_open
            FROM `%s` 
        """,
        competitors_id,
        competitors_geom,
        competitors_table
        );
    END IF;

    EXECUTE IMMEDIATE FORMAT('''
    %s
    AS
    %s
    %s
    %s
    ORDER BY facility_id
    ''',
    create_output_query,
    candidates_query,
    required_query,
    competitors_query
    );

    -- Raise error if facility_id is not unique
    SET query = FORMAT("""
        SELECT COUNT(DISTINCT facility_id) != COUNT(*)
        FROM `%s`
    """, output_table);
    EXECUTE IMMEDIATE query INTO flag;
    IF flag THEN
        RAISE USING MESSAGE = 'Duplicates found in overall facily IDs. Please make sure facility IDs are unique across all facility types.';  
    END IF;

    -- Raise error if min_usage > max_capacity
    IF min_usage_bool AND max_capacity_bool THEN
        SET query = FORMAT("""
            SELECT COUNTIF(min_usage <= max_capacity) != COUNT(*)
            FROM `%s`
            WHERE facility_type != 2
        """, output_table);
        EXECUTE IMMEDIATE query INTO flag;
        IF flag THEN
            RAISE USING MESSAGE = 'Minimum capacity cannot be larger than maximum capacity';
        END IF;
    END IF;

    -- Drop tables in case of error & propagate the original error
    EXCEPTION
        WHEN ERROR THEN
            IF (output_table IS NOT NULL) THEN
                EXECUTE IMMEDIATE FORMAT('DROP TABLE IF EXISTS `%s`', output_table);
            END IF;
            RAISE;

END;
END;