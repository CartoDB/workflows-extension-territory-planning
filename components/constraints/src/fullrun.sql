DECLARE compatibility_tablename STRING DEFAULT NULL;
DECLARE compatibility_metadata STRING DEFAULT NULL;
DECLARE compatible_query STRING DEFAULT NULL;
DECLARE uncompatible_query STRING DEFAULT NULL;
DECLARE out_table STRING;
DECLARE query STRING;
DECLARE flag BOOL;

BEGIN

BEGIN

    SET out_table = REPLACE(output_table, '`', '');

    -- 1. Create metadata table (ouput)
    EXECUTE IMMEDIATE FORMAT("""
        CREATE TABLE IF NOT EXISTS `%s` (   
            constraint_id STRING,
            constraint_description STRING,
            table_name STRING
        )
        OPTIONS (expiration_timestamp = TIMESTAMP_ADD(CURRENT_TIMESTAMP(), INTERVAL 30 DAY)) 
    """,
    out_table
    );

    -- 2. Add available constraints
    EXECUTE IMMEDIATE FORMAT("""
        INSERT INTO `%s` 
        VALUES (   
            'compatibility',
            'Force facility-customer relationships',
            NULL
        )
    """,
    out_table
    );

    -- 3. Create auxiliary tables and update metadata if specified
    
    -- Constraint ID: compatibility
    IF compatible_bool OR uncompatible_bool THEN
        SET compatibility_tablename = FORMAT('%s_compatibility', out_table);
        EXECUTE IMMEDIATE FORMAT("""
            UPDATE `%s`
            SET table_name = '%s'
            WHERE constraint_id = 'compatibility';
        """,
        out_table,
        compatibility_tablename
        );

        IF compatible_bool THEN
            SET compatible_query = FORMAT("""
                SELECT DISTINCT
                    CAST(%s AS STRING) AS facility_id,
                    CAST(%s AS STRING) AS customer_id,
                    1 AS compatibility
                FROM `%s`
            """,
            compatible_facility_id,
            compatible_customer_id,
            REPLACE(compatible_table, '`', '')
            );
        END IF;

        IF uncompatible_bool THEN
            SET uncompatible_query = FORMAT("""
                SELECT DISTINCT
                    CAST(%s AS STRING) AS facility_id,
                    CAST(%s AS STRING) AS customer_id,
                    0 AS compatibility
                FROM `%s`
            """,
            uncompatible_facility_id,
            uncompatible_customer_id,
            REPLACE(uncompatible_table, '`', '')
            );
        END IF;

        EXECUTE IMMEDIATE FORMAT("""
            CREATE TABLE IF NOT EXISTS `%s` 
            OPTIONS (expiration_timestamp = TIMESTAMP_ADD(CURRENT_TIMESTAMP(), INTERVAL 30 DAY)) 
            AS
                %s
                ORDER BY facility_id, customer_id
        """,
        compatibility_tablename,
        ARRAY_TO_STRING(
            ARRAY(SELECT x FROM UNNEST([compatible_query,uncompatible_query]) AS x WHERE x IS NOT NULL),
            ' UNION ALL ')
        );

        SET query = FORMAT("""
            SELECT COUNT(*) != COUNT(DISTINCT CONCAT(facility_id, '-', customer_id))
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
            IF (out_table IS NOT NULL) THEN
                EXECUTE IMMEDIATE FORMAT('DROP TABLE IF EXISTS `%s`', out_table);
            END IF;
            IF (compatibility_tablename IS NOT NULL) THEN
                EXECUTE IMMEDIATE FORMAT('DROP TABLE IF EXISTS `%s`', compatibility_tablename);
            END IF;
            RAISE;
END;
END;

