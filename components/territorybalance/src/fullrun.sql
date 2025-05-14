DECLARE output_temp_scoring STRING;
DECLARE create_output_query STRING;
DECLARE query STRING;
DECLARE row_count INT64;
DECLARE condition STRING;
DECLARE options STRING DEFAULT """{"scoring_method":"CUSTOM_WEIGHTS","scaling":"MIN_MAX_SCALER","aggregation":"LINEAR","return_range":[0,1]}""";
DECLARE temp_uuid STRING;
DECLARE temp_table STRING;

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
            CAST(b.%s AS FLOAT64) AS %s,
            a.spatial_score as score
    FROM `%s` a
    JOIN `%s` b
    USING(%s)
    ''',
    output_temp_scoring,
    index_column,
    demand_column, demand_column,
    output_temp_scoring,
    input_table,
    index_column
    );

ELSE 

    EXECUTE IMMEDIATE FORMAT('''
    CREATE OR REPLACE TABLE `%s` AS
    SELECT  %s,
            CAST(%s AS FLOAT64) AS %s,
            %s AS score
    FROM `%s`
    ''',
    output_temp_scoring,
    index_column,
    demand_column, demand_column,
    IF(similarity_feats IS NULL OR similarity_feats='', '1.0', FORMAT('ML.MIN_MAX_SCALER(%s) OVER()', similarity_feats)), 
    input_table
    ); 

END IF;

-- Call remote function and run territory optimization  
CALL `carto-territory-balancing`.accessors.TERRITORY_BALANCING(
    FORMAT(''' SELECT * FROM `%s` ''', output_temp_scoring),
    index_column,
    output_temp_scoring,
    demand_column,
    FORMAT('%d',CAST(npartitions AS INT64)),
    0.05
    );

-- Append input columns if specified
EXECUTE IMMEDIATE FORMAT('''
    %s AS SELECT * FROM `%s` %s
''',
create_output_query,
output_temp_scoring,
IF(keep_input_columns, FORMAT('JOIN `%s` USING(%s)', input_table, index_column), '')
);

-- Drop temporal table
EXECUTE IMMEDIATE FORMAT('DROP TABLE IF EXISTS `%s`', output_temp_scoring);
