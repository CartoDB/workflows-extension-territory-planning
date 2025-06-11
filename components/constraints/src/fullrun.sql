DECLARE compatibility_tablename STRING DEFAULT NULL;
DECLARE compatibility_metadata STRING DEFAULT NULL;
DECLARE matches_query STRING DEFAULT NULL;
DECLARE unmatches_query STRING DEFAULT NULL;

BEGIN
    -- Create metadata table (ouput)
    EXECUTE IMMEDIATE FORMAT("""
        CREATE TABLE IF NOT EXISTS `%s` (   
            constraint_id STRING,
            constraint_description STRING,
            table_name STRING
        )
        OPTIONS (expiration_timestamp = TIMESTAMP_ADD(CURRENT_TIMESTAMP(), INTERVAL 30 DAY)) 
    """,
    REPLACE(output_table, '`', '')
    );
    EXECUTE IMMEDIATE FORMAT("""
        INSERT INTO `%s` 
        VALUES (   
            'compatibility',
            'Required facility-customer pairs',
            NULL
        )
    """,
    REPLACE(output_table, '`', '')
    );

    -- Create auxiliary tables and update metadata
    IF matches_bool OR unmatches_bool THEN
        SET compatibility_tablename = FORMAT('%s_matches', REPLACE(output_table, '`', ''));
        EXECUTE IMMEDIATE FORMAT("""
            UPDATE `%s`
            SET table_name = '%s'
            WHERE constraint_id = 'compatibility';
        """,
        REPLACE(output_table, '`', ''),
        compatibility_tablename
        );

        IF matches_bool THEN
            SET matches_query = FORMAT("""
                SELECT 
                    CAST(%s AS STRING) AS facility_id,
                    CAST(%s AS STRING) AS customer_id,
                    1 AS compatibility
                FROM `%s`
            """,
            matches_facility_id,
            matches_customer_id,
            REPLACE(matches_table, '`', '')
            );
        END IF;

        IF unmatches_bool THEN
            SET unmatches_query = FORMAT("""
                SELECT 
                    CAST(%s AS STRING) AS facility_id,
                    CAST(%s AS STRING) AS customer_id,
                    0 AS compatibility
                FROM `%s`
            """,
            unmatches_facility_id,
            unmatches_customer_id,
            REPLACE(unmatches_table, '`', '')
            );
        END IF;

        EXECUTE IMMEDIATE FORMAT("""
            CREATE TABLE IF NOT EXISTS `%s` 
            OPTIONS (expiration_timestamp = TIMESTAMP_ADD(CURRENT_TIMESTAMP(), INTERVAL 30 DAY)) 
            AS
                %s
        """,
        compatibility_tablename,
        ARRAY_TO_STRING(
            ARRAY(SELECT x FROM UNNEST([matches_query,unmatches_query]) AS x WHERE x IS NOT NULL),
            ' UNION ALL ')
        );

    END IF;

END;

