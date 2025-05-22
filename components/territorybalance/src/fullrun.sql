DECLARE output_temp_scoring STRING;
DECLARE create_output_query STRING;
DECLARE query STRING;
DECLARE row_count INT64;
DECLARE dups_flag BOOL;
DECLARE condition STRING;
DECLARE options STRING DEFAULT """{"scoring_method":"CUSTOM_WEIGHTS","scaling":"MIN_MAX_SCALER","aggregation":"LINEAR","return_range":[0,1]}""";
DECLARE temp_uuid STRING;
DECLARE temp_table STRING;
DECLARE grid_type STRING;
DECLARE grid_resolution INT64;

BEGIN

    SET input_table = REPLACE(input_table, '`', '');
    SET output_table = REPLACE(output_table, '`', '');

    -- Set variables based on whether the workflow is executed via API
    IF REGEXP_CONTAINS(output_table, r'^[^.]+\.[^.]+\.[^.]+$') THEN
        SET create_output_query = FORMAT('CREATE TABLE IF NOT EXISTS `%s` OPTIONS (expiration_timestamp = TIMESTAMP_ADD(CURRENT_TIMESTAMP(), INTERVAL 30 DAY))', output_table);
        SET output_temp_scoring = CONCAT(output_table, "_temp_scoring");
    ELSE
        -- Output needs to be qualified with tempStoragePath, meaning an API execution of the Workflow
        SET create_output_query = FORMAT('CREATE TEMPORARY TABLE `%s`', output_table);
        SET temp_uuid = GENERATE_UUID();
        SET temp_table = CONCAT(REPLACE(tempStoragePath, '"', ''), '.WORKFLOW_', temp_uuid, '_intermediate');
        SET output_temp_scoring = CONCAT(temp_table, "_temp_scoring");
    END IF;

    -- 1. Check inputs
    -- Raise error if index_column not QUADBIN | H3 
    CALL `carto-un`.carto.__CHECK_GRID_INDEX_COLUMN(
        FORMAT('SELECT %s FROM `%s`', index_column, input_table),
        index_column,
        grid_type,
        grid_resolution
    );
    IF grid_type = 'unsupported' OR grid_type IS NULL THEN
        RAISE USING MESSAGE = FORMAT('Please select a valid index column (H3 or QUADBIN format).');
    END IF;

    -- Raise error if NULL values
    SET condition = ARRAY_TO_STRING(ARRAY(
    SELECT w || ' IS NULL' 
    FROM UNNEST (SPLIT(CONCAT(index_column, ',', demand_column, ',', IFNULL(similarity_feats, '')),',')) AS w
    WHERE w != ''
    ), ' OR ');

    SET query = FORMAT("""
        SELECT COUNT(*) 
        FROM `%s`
        WHERE %s
    """, input_table, condition);

    EXECUTE IMMEDIATE query INTO row_count;

    IF row_count > 0 THEN
        RAISE USING MESSAGE = FORMAT('Input variables cannot be NULL. Please remove and/or impute missing values before running territory balance.');
    END IF;

    -- Raise error if index column not unique
    SET query = FORMAT("""
        SELECT COUNT(*) > COUNT(DISTINCT %s)
        FROM `%s`
    """, index_column, input_table);

    EXECUTE IMMEDIATE query INTO dups_flag;

    IF dups_flag THEN
        RAISE USING MESSAGE = FORMAT('Input index column must be unique. Please remove duplicated values before running territory balance.');
    END IF;

    -- 2. Prepare input
    -- Run composite score if more than one variable is selected       
    IF ARRAY_LENGTH(SPLIT(similarity_feats,',')) > 1 THEN

        CALL `carto-un`.carto.CREATE_SPATIAL_COMPOSITE_UNSUPERVISED(
            FORMAT(
                'SELECT %s, %s FROM `%s`',
                    index_column, 
                    similarity_feats, 
                    input_table
                ), 
            index_column, 
            output_temp_scoring, 
            options);

        EXECUTE IMMEDIATE FORMAT('''
        CREATE OR REPLACE TABLE `%s` AS
        SELECT  a.%s,
                CAST(b.%s AS FLOAT64) AS demand,
                a.spatial_score as score
        FROM `%s` a
        JOIN `%s` b
        USING(%s)
        ''',
        output_temp_scoring,
        index_column,
        demand_column,
        output_temp_scoring,
        input_table,
        index_column
        );

    ELSE 

        EXECUTE IMMEDIATE FORMAT('''
        CREATE OR REPLACE TABLE `%s` AS
        SELECT  %s AS geoid,
                CAST(%s AS FLOAT64) AS demand,
                %s AS score
        FROM `%s`
        ''',
        output_temp_scoring,
        index_column,
        demand_column,
        IF(similarity_feats IS NULL OR similarity_feats='', '1.0', FORMAT('ML.MIN_MAX_SCALER(%s) OVER()', similarity_feats)), 
        input_table
        ); 

    END IF;

    -- 3. Call remote function to run territory optimization  
    -- TODO: deploy in `cartobq.us`
    EXECUTE IMMEDIATE FORMAT('''
        %s AS 
        WITH T1 AS (
            SELECT `cartodb-on-gcp-datascience`.lgarciaduarte.TERRITORY_BALANCE_CLOUDRUN(
                JSON_OBJECT("geoid", ARRAY_AGG(geoid)),
                JSON_OBJECT("demand", ARRAY_AGG(demand)),
                JSON_OBJECT("score", ARRAY_AGG(score)),
                %d,
                0.05,
                '%s'
            ) result
            FROM `%s`
        ), T2 AS (
            SELECT
                %s AS %s,
                CAST(cluster AS INT64) AS cluster
            FROM T1, UNNEST(JSON_EXTRACT_STRING_ARRAY(result,'$.geoid')) AS geoid WITH OFFSET AS geoid_offset
            JOIN UNNEST(JSON_EXTRACT_STRING_ARRAY(result,'$.cluster')) AS cluster WITH OFFSET AS cluster_offset
            ON geoid_offset = cluster_offset
        )
        SELECT %s FROM T2 %s
    ''',
    create_output_query,
    CAST(npartitions AS INT64),
    grid_type,
    output_temp_scoring,
    IF(grid_type = 'h3', 'geoid', 'CAST(geoid AS INT64)'), index_column,
    IF(keep_input_columns, 'T3.*, T2.cluster', FORMAT('%s, cluster', index_column)),
    IF(keep_input_columns, FORMAT('JOIN `%s` as T3 USING(%s)', input_table, index_column), '')
    );

    -- Drop temporal table
    EXECUTE IMMEDIATE FORMAT('DROP TABLE IF EXISTS `%s`', output_temp_scoring);

    EXCEPTION WHEN ERROR THEN
        EXECUTE IMMEDIATE FORMAT(""" DROP TABLE IF EXISTS `%s` """, output_temp_scoring);
        -- Propagate the original error
        RAISE USING MESSAGE = @@error.message;

END;