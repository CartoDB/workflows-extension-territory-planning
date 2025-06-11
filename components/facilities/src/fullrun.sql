DECLARE candidates_query STRING DEFAULT '';
DECLARE required_query STRING DEFAULT '';
DECLARE competitors_query STRING DEFAULT '';

-- TODO: check unique IDs per type of facility, raise error accordingly
BEGIN
    SET candidates_query = FORMAT("""
        SELECT 
            CAST(%s AS STRING) AS facility_id,
            %s AS geom,
            'candidate' AS facility_type,
            CAST(%s AS STRING) AS group_id,
            %s AS min_capacity,
            %s AS max_capacity,
            %s AS cost_of_open
        FROM `%s` 

    """,
    candidates_id,
    candidates_geom,
    IF(group_bool, candidates_group, 'NULL'),
    IF(min_capacity_bool, candidates_min_capacity, 'NULL'),
    IF(max_capacity_bool, candidates_max_capacity, 'NULL'),
    IF(costofopen_bool, candidates_costofopen, 'NULL'),
    REPLACE(candidates_table, '`', '')
    );

    IF required_bool THEN
        SET required_query = FORMAT("""
            UNION ALL
            SELECT 
                CAST(%s AS STRING) AS facility_id,
                %s AS geom,
                'required' AS facility_type,
                CAST(%s AS STRING) AS group_id,
                %s AS min_capacity,
                %s AS max_capacity,
                %s AS cost_of_open
            FROM `%s` 

        """,
        required_id,
        required_geom,
        IF(group_bool, required_group, 'NULL'),
        IF(min_capacity_bool, required_min_capacity, 'NULL'),
        IF(max_capacity_bool, required_max_capacity, 'NULL'),
        IF(costofopen_bool, required_costofopen, 'NULL'),
        REPLACE(required_table, '`', '')
        );
    END IF;

    IF competitors_bool THEN
        SET competitors_query = FORMAT("""
            UNION ALL
            SELECT 
                CAST(%s AS STRING) AS facility_id,
                %s AS geom,
                'competitor' AS facility_type,
                NULL AS group_id,
                NULL AS min_capacity,
                NULL AS max_capacity,
                NULL AS cost_of_open
            FROM `%s` 

        """,
        competitors_id,
        competitors_geom,
        REPLACE(competitors_table, '`', '')
        );
    END IF;

    EXECUTE IMMEDIATE FORMAT('''
    CREATE TABLE IF NOT EXISTS `%s` 
    OPTIONS (expiration_timestamp = TIMESTAMP_ADD(CURRENT_TIMESTAMP(), INTERVAL 30 DAY)) 
    AS
    %s
    %s
    %s
    ''',
    REPLACE(output_table, '`', ''),
    candidates_query,
    required_query,
    competitors_query
    );

END;