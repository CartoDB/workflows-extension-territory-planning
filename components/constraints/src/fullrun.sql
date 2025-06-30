DECLARE compatibility_tablename STRING DEFAULT NULL;
DECLARE compatibility_metadata STRING DEFAULT NULL;
DECLARE compatible_query STRING DEFAULT NULL;
DECLARE uncompatible_query STRING DEFAULT NULL;
DECLARE query STRING;
DECLARE flag BOOL;
DECLARE create_output_query STRING;
DECLARE create_compatibility_query STRING;

BEGIN

BEGIN

    SET output_table = REPLACE(output_table, '`', '');
    SET compatibility_tablename = FORMAT('%s_compatibility', output_table);

    -- Set variables based on whether the workflow is executed via API
    IF REGEXP_CONTAINS(output_table, r'^[^.]+\.[^.]+\.[^.]+$') THEN
        SET create_output_query = FORMAT('CREATE TABLE IF NOT EXISTS `%s` (constraint_id STRING, constraint_description STRING, table_name STRING) OPTIONS (expiration_timestamp = TIMESTAMP_ADD(CURRENT_TIMESTAMP(), INTERVAL 30 DAY))', output_table);
        SET create_compatibility_query = FORMAT('CREATE TABLE IF NOT EXISTS `%s` OPTIONS (expiration_timestamp = TIMESTAMP_ADD(CURRENT_TIMESTAMP(), INTERVAL 30 DAY))', compatibility_tablename);
    ELSE
        -- Output needs to be qualified with tempStoragePath, meaning an API execution of the Workflow
        SET create_output_query = FORMAT('CREATE TEMPORARY TABLE `%s` (constraint_id STRING, constraint_description STRING, table_name STRING)', output_table);
        SET create_compatibility_query = FORMAT('CREATE TEMPORARY TABLE `%s`', compatibility_tablename);
    END IF;


    -- 1. Create metadata table (ouput)
    EXECUTE IMMEDIATE FORMAT("""
        %s 
    """,
    create_output_query
    );

    -- 2. Add available constraints
    EXECUTE IMMEDIATE FORMAT("""
        INSERT INTO `%s` 
        VALUES (   
            'compatibility',
            'Force facility-demand point relationships',
            NULL
        )
    """,
    output_table
    );

    -- 3. Create auxiliary tables and update metadata if specified
    
    -- Constraint ID: compatibility
    IF compatible_bool OR uncompatible_bool THEN
        EXECUTE IMMEDIATE FORMAT("""
            UPDATE `%s`
            SET table_name = '%s'
            WHERE constraint_id = 'compatibility';
        """,
        output_table,
        compatibility_tablename
        );

        IF compatible_bool THEN
            SET compatible_query = FORMAT("""
                SELECT DISTINCT
                    CAST(%s AS STRING) AS facility_id,
                    CAST(%s AS STRING) AS dpoint_id,
                    1 AS compatibility
                FROM `%s`
            """,
            compatible_facility_id,
            compatible_dpoint_id,
            REPLACE(compatible_table, '`', '')
            );
        END IF;

        IF uncompatible_bool THEN
            SET uncompatible_query = FORMAT("""
                SELECT DISTINCT
                    CAST(%s AS STRING) AS facility_id,
                    CAST(%s AS STRING) AS dpoint_id,
                    0 AS compatibility
                FROM `%s`
            """,
            uncompatible_facility_id,
            uncompatible_dpoint_id,
            REPLACE(uncompatible_table, '`', '')
            );
        END IF;

        EXECUTE IMMEDIATE FORMAT("""
            %s
            AS
                %s
                ORDER BY facility_id, dpoint_id
        """,
        create_compatibility_query,
        ARRAY_TO_STRING(
            ARRAY(SELECT x FROM UNNEST([compatible_query,uncompatible_query]) AS x WHERE x IS NOT NULL),
            ' UNION ALL ')
        );

        SET query = FORMAT("""
            SELECT COUNT(*) != COUNT(DISTINCT CONCAT(facility_id, '-', dpoint_id))
            FROM `%s`
        """, compatibility_tablename);
        EXECUTE IMMEDIATE query INTO flag;
        IF flag THEN
            RAISE USING MESSAGE = 'Found conflicting compatibility values for facility-client pair(s): a pair cannot be both compatible and incompatible.';
        END IF;

    END IF;

    -- Drop tables in case of error & propagate the original error
    EXCEPTION
        WHEN ERROR THEN
            IF (output_table IS NOT NULL) THEN
                EXECUTE IMMEDIATE FORMAT('DROP TABLE IF EXISTS `%s`', output_table);
            END IF;
            IF (compatibility_tablename IS NOT NULL) THEN
                EXECUTE IMMEDIATE FORMAT('DROP TABLE IF EXISTS `%s`', compatibility_tablename);
            END IF;
            RAISE;
END;
END;

