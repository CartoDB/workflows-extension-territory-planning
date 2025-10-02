DECLARE c_compatibility_table STRING DEFAULT NULL;
DECLARE c_compatibility_query STRING DEFAULT '';
DECLARE c_compatibility_join STRING DEFAULT '';
DECLARE output_table_temp STRING;
DECLARE opt_strategy STRING;
DECLARE query STRING;
DECLARE flag BOOL;
DECLARE create_output_query STRING;
DECLARE create_metrics_query STRING;
DECLARE temp_uuid STRING;
DECLARE temp_table STRING;

BEGIN

    SET output_table = REPLACE(output_table, '`', '');
    SET metrics_table = REPLACE(metrics_table, '`', '');

    -- Set variables based on whether the workflow is executed via API
    IF REGEXP_CONTAINS(output_table, r'^[^.]+\.[^.]+\.[^.]+$') THEN
        SET create_output_query = FORMAT('CREATE TABLE IF NOT EXISTS `%s` OPTIONS (expiration_timestamp = TIMESTAMP_ADD(CURRENT_TIMESTAMP(), INTERVAL 30 DAY))', output_table);
        SET create_metrics_query = FORMAT('CREATE TABLE IF NOT EXISTS `%s` OPTIONS (expiration_timestamp = TIMESTAMP_ADD(CURRENT_TIMESTAMP(), INTERVAL 30 DAY))', metrics_table);
        SET output_table_temp = CONCAT(REPLACE(output_table, '`', ''), "_temp");
    ELSE
        -- Output needs to be qualified with tempStoragePath, meaning an API execution of the Workflow
        SET create_output_query = FORMAT('CREATE TEMPORARY TABLE `%s`', output_table);
        SET create_metrics_query = FORMAT('CREATE TEMPORARY TABLE `%s`', metrics_table);
        SET temp_uuid = GENERATE_UUID();
        SET temp_table = CONCAT(REPLACE(tempStoragePath, '"', ''), '.WORKFLOW_', temp_uuid, '_intermediate');
        SET output_table_temp = CONCAT(temp_table, "_temp_scoring");
    END IF;

    -- 1. Check input params
    -- No checks needed, data was checked using 'Prepare x' components. 
    -- If there are NULLs in input columns, an error will occurr when calling LOCATION_ALLOCATION avoiding doing intensive checks

    SET opt_strategy =  CASE optimization_strategy
        WHEN 'Minimize maximum cost' THEN 'minimize_max_cost'
        WHEN 'Maximize coverage' THEN 'maximize_coverage'
        ELSE 'minimize_total_cost'
    END;

    -- 2. Check input data
    SET query = FORMAT("""
        SELECT COUNTIF(
            COALESCE(t1.facility_id,'') != COALESCE(t2.facility_id,'') 
            OR
            COALESCE(t1.dpoint_id,'') != COALESCE(t2.dpoint_id,'')
        ) != 0
        FROM `%s` t1
        RIGHT JOIN (
            SELECT facility_id, dpoint_id
            FROM `%s` CROSS JOIN `%s`
            %s
        ) t2
        ON t1.facility_id = t2.facility_id AND t1.dpoint_id = t2.dpoint_id
    """,
    REPLACE(costs_table, '`', ''),
    REPLACE(facilities_table, '`', ''),
    REPLACE(dpoints_table, '`', ''),
    CASE 
        WHEN NOT competitor_facilities_bool AND NOT required_facilities_bool THEN 'WHERE facility_type = 0'
        WHEN NOT competitor_facilities_bool AND required_facilities_bool THEN 'WHERE facility_type != 2'
        WHEN competitor_facilities_bool AND NOT required_facilities_bool THEN 'WHERE facility_type != 1'
        ELSE ''
    END
    );
    EXECUTE IMMEDIATE query INTO flag;
    IF flag THEN
        RAISE USING MESSAGE = 'Missing costs detected. Please assign one cost for each facility-demand point pair.';
    END IF;

    -- Check if competitor facilities exist when competitor_facilities_bool is enabled
    IF competitor_facilities_bool THEN
        SET query = FORMAT("""
            SELECT COUNT(*) = 0
            FROM `%s`
            WHERE facility_type = 2
        """,
        REPLACE(facilities_table, '`', '')
        );
        EXECUTE IMMEDIATE query INTO flag;
        IF flag THEN
            RAISE USING MESSAGE = 'No competitor facilities found. Please add competitor facilities (facility_type = 2) or disable competitor facilities option.';
        END IF;
    END IF;

    -- Check if required facilities exist when required_facilities_bool is enabled
    IF required_facilities_bool THEN
        SET query = FORMAT("""
            SELECT COUNT(*) = 0
            FROM `%s`
            WHERE facility_type = 1
        """,
        REPLACE(facilities_table, '`', '')
        );
        EXECUTE IMMEDIATE query INTO flag;
        IF flag THEN
            RAISE USING MESSAGE = 'No required facilities found. Please add required facilities (facility_type = 1) or disable required facilities option.';
        END IF;
    END IF;

    -- Check if min_usage values exist when facilities_min_usage_bool is enabled
    IF facilities_min_usage_bool THEN
        SET query = FORMAT("""
            SELECT COUNT(*) > 0
            FROM `%s`
            WHERE min_usage IS NULL AND facility_type != 2
        """,
        REPLACE(facilities_table, '`', '')
        );
        EXECUTE IMMEDIATE query INTO flag;
        IF flag THEN
            RAISE USING MESSAGE = 'Missing min_usage values detected. Please provide min_usage values for all facilities or disable minimum usage option.';
        END IF;
    END IF;

    -- Check if max_capacity values exist when facilities_max_capacity_bool is enabled
    IF facilities_max_capacity_bool THEN
        SET query = FORMAT("""
            SELECT COUNT(*) > 0
            FROM `%s`
            WHERE max_capacity IS NULL AND facility_type != 2
        """,
        REPLACE(facilities_table, '`', '')
        );
        EXECUTE IMMEDIATE query INTO flag;
        IF flag THEN
            RAISE USING MESSAGE = 'Missing max_capacity values detected. Please provide max_capacity values for all facilities or disable maximum capacity option.';
        END IF;
    END IF;

    -- Check if demand values exist when demand_bool is enabled
    IF demand_bool THEN
        SET query = FORMAT("""
            SELECT COUNT(*) > 0
            FROM `%s`
            WHERE demand IS NULL
        """,
        REPLACE(dpoints_table, '`', '')
        );
        EXECUTE IMMEDIATE query INTO flag;
        IF flag THEN
            RAISE USING MESSAGE = 'Missing demand values detected. Please provide demand values for all demand points or disable demand option.';
        END IF;
    END IF;

    -- Check if cost_of_open values exist when costopen_facilities_bool is enabled
    IF (costopen_facilities_bool OR budget_constraint_bool) THEN
        SET query = FORMAT("""
            SELECT COUNT(*) > 0
            FROM `%s`
            WHERE cost_of_open IS NULL AND facility_type = 0
        """,
        REPLACE(facilities_table, '`', '')
        );
        EXECUTE IMMEDIATE query INTO flag;
        IF flag THEN
            RAISE USING MESSAGE = 'Missing cost_of_open values detected. Please provide cost_of_open values for all candidate facilities or disable cost of opening and/or budget options.';
        END IF;
    END IF;

    -- Check if group_id values exist when limit_facilities_group_bool is enabled
    IF limit_facilities_group_bool THEN
        SET query = FORMAT("""
            SELECT COUNT(*) > 0
            FROM `%s`
            WHERE group_id IS NULL AND facility_type != 2
        """,
        REPLACE(facilities_table, '`', '')
        );
        EXECUTE IMMEDIATE query INTO flag;
        IF flag THEN
            RAISE USING MESSAGE = 'Missing group_id values detected. Please provide group_id values for all facilities or disable facility group limit option.';
        END IF;
    END IF;

    -- 3. Run Location Allocation
    IF compatibility_bool THEN

        IF constraints_table IS NULL THEN
            RAISE USING MESSAGE = 'Please connect a `Prepare Constraints data` component to force facility-demand point relationships.';
        END IF;

        EXECUTE IMMEDIATE FORMAT('''SELECT table_name FROM `%s` WHERE constraint_id = "compatibility" ''', REPLACE(constraints_table, '`', ''))
        INTO c_compatibility_table;

        IF c_compatibility_table IS NULL THEN
            RAISE USING MESSAGE = 'Please use a `Prepare Constraints data` component to prepare the necessary data to force facility-demand point relationships.';
        END IF;

        SET c_compatibility_query = FORMAT('''
        , c_compatibility AS (
            SELECT
                ARRAY_AGG(CAST(c.facility_id AS STRING)) compatibility_facility_id,
                ARRAY_AGG(CAST(c.dpoint_id AS STRING)) compatibility_dpoint_id,
                ARRAY_AGG(CAST(c.compatibility AS INT64)) compatibility_type
            FROM `%s` c
            INNER JOIN facilities_no_comp f USING (facility_id)
            INNER JOIN dpoints_no_comp dc USING (dpoint_id)
        )
        ''',
        REPLACE(c_compatibility_table, '`', '')
        );

        SET c_compatibility_join = "CROSS JOIN c_compatibility";
    END IF;

    EXECUTE IMMEDIATE FORMAT('''
    CREATE OR REPLACE TABLE `%s` 
    OPTIONS (expiration_timestamp = TIMESTAMP_ADD(CURRENT_TIMESTAMP(), INTERVAL 30 DAY))
    AS
    WITH 
    facilities_no_comp AS (
        -- Required and candidate facilities
        SELECT
            facility_id,
            facility_type,
            %s AS facility_group_id,
            %s AS facility_min_usage,
            %s AS facility_max_capacity,
            %s AS facility_cost_of_open
        FROM `%s`
        WHERE facility_type != 2  -- remove competitors
    ),
    dpoints_comp AS (
        -- Dpoints in costs captured by competitors
        SELECT DISTINCT c.dpoint_id
        FROM `%s` c
        JOIN `%s` f
        ON c.facility_id = f.facility_id
        WHERE f.facility_type = 2 AND c.cost <= %f
    ),
    dpoints_no_comp AS (
        -- Dpoints not captured by competitors
        SELECT
            d.dpoint_id,
            %s AS demand
        FROM `%s` d
        LEFT JOIN dpoints_comp dc ON d.dpoint_id = dc.dpoint_id
        WHERE dc.dpoint_id IS NULL
    ),
    facilities AS (
        SELECT 
            ARRAY_AGG(CAST(facility_id AS STRING)) facility_id,
            ARRAY_AGG(CAST(facility_type AS INT64)) facility_type,
            ARRAY_AGG(CAST(facility_group_id AS STRING)) facility_group_id,                            
            ARRAY_AGG(CAST(facility_min_usage AS FLOAT64)) facility_min_usage,                       
            ARRAY_AGG(CAST(facility_max_capacity AS FLOAT64)) facility_max_capacity,
            ARRAY_AGG(CAST(facility_cost_of_open AS FLOAT64)) facility_cost_of_open
        FROM facilities_no_comp
    ),
    dpoints AS (
        SELECT
            ARRAY_AGG(CAST(dpoint_id AS STRING)) dpoint_id,
            ARRAY_AGG(CAST(demand AS FLOAT64)) dpoint_demand
        FROM dpoints_no_comp
    ),
    costs AS (
        SELECT 
            ARRAY_AGG(CAST(c.facility_id AS STRING)) cost_facility_id,
            ARRAY_AGG(CAST(c.dpoint_id AS STRING)) cost_dpoint_id,
            ARRAY_AGG(CAST(c.cost AS FLOAT64)) cost
        FROM `%s` c
        INNER JOIN facilities_no_comp f USING (facility_id)
        INNER JOIN dpoints_no_comp d USING (dpoint_id)
    )
    %s
    SELECT  *
    FROM facilities CROSS JOIN dpoints CROSS JOIN costs %s
    ''',
    output_table_temp,
    -- facilities_no_comp
    IF(limit_facilities_group_bool, 'group_id', 'COALESCE(group_id,"0")'),
    IF(facilities_min_usage_bool, 'min_usage', 'COALESCE(min_usage,0)'),
    IF(facilities_max_capacity_bool, 'max_capacity', 'COALESCE(max_capacity,0)'),
    IF(costopen_facilities_bool, 'cost_of_open', 'COALESCE(cost_of_open,0)'),
    REPLACE(facilities_table, '`', ''),
    -- dpoints_comp
    REPLACE(costs_table, '`', ''),
    REPLACE(facilities_table, '`', ''),
    IF(competitor_facilities_bool, competitor_trade_area, -1),
    -- dpoints_no_comp
    IF(demand_bool, 'd.demand', 'COALESCE(d.demand,0)'),
    REPLACE(dpoints_table, '`', ''),
    -- costs
    REPLACE(costs_table, '`', ''),
    -- constraints
    c_compatibility_query,
    c_compatibility_join
    );

    EXECUTE IMMEDIATE FORMAT('''
    CREATE OR REPLACE TABLE `%s` 
    OPTIONS (expiration_timestamp = TIMESTAMP_ADD(CURRENT_TIMESTAMP(), INTERVAL 30 DAY))
    AS
    SELECT s.facility_id, s.dpoint_id, s.demand, s.objective_value, s.gap, s.solving_time, s.termination_reason, s.stats
    FROM `%s`, UNNEST(@@workflows_temp@@.`LOCATION_ALLOCATION`
    (    
        '%s',
        facility_id,
        facility_type,
        facility_group_id,
        facility_min_usage,
        facility_max_capacity,
        facility_cost_of_open,
        dpoint_id,
        dpoint_demand,
        cost_facility_id,
        cost_dpoint_id,
        cost,
        %s,
        %s,
        %s,
        %t, 
        %s,
        %s,
        %t,
        %t,
        %t,
        %t,
        %t,
        %f,
        %s,
        %d,
        %d,
        False
    )) s
    ''',
    output_table_temp,
    output_table_temp,
    opt_strategy,
    IF(compatibility_bool, 'compatibility_facility_id', 'NULL'),
    IF(compatibility_bool, 'compatibility_dpoint_id', 'NULL'),
    IF(compatibility_bool, 'compatibility_type', 'NULL'),
    required_facilities_bool, 
    IF(limit_facilities_bool, CAST(max_facilities AS STRING), 'NULL'), 
    IF(limit_facilities_group_bool, CAST(max_facilities_group AS STRING), 'NULL'), 
    facilities_min_usage_bool,
    facilities_max_capacity_bool,
    compatibility_bool,
    demand_bool,
    costopen_facilities_bool,
    IFNULL(coverage_radius,0),
    IF(budget_constraint_bool, CAST(budget_constraint AS STRING),'NULL'),
    CAST(time_limit AS INT64),
    CAST(relative_gap AS INT64)
    );

    -- 4. Extract output
    EXECUTE IMMEDIATE FORMAT('''
    %s
    AS
        SELECT facility_id, dpoint_id, demand, ST_MAKELINE(f.geom, c.geom) geom
        FROM `%s`
        JOIN  (SELECT facility_id, geom FROM `%s`) f
        USING (facility_id)
        JOIN   (SELECT dpoint_id, geom FROM `%s`) c
        USING (dpoint_id)
        ORDER BY facility_id, dpoint_id
    ''',
    create_output_query,
    output_table_temp,
    REPLACE(facilities_table, '`', ''),
    REPLACE(dpoints_table, '`', '')
    );

    EXECUTE IMMEDIATE FORMAT('''
    %s
    AS
        SELECT objective_value, gap, solving_time, termination_reason, stats
        FROM `%s`
        ORDER BY termination_reason NULLS LAST
        LIMIT 1
    ''',
    create_metrics_query,
    output_table_temp
    );

    EXECUTE IMMEDIATE FORMAT('''
    DROP TABLE `%s`;
    ''',
    output_table_temp
    );

END;
