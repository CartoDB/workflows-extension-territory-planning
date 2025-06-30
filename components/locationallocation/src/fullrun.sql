DECLARE c_compatibility_table STRING DEFAULT NULL;
DECLARE c_compatibility_query STRING DEFAULT '';
DECLARE c_compatibility_join STRING DEFAULT '';
DECLARE output_table_temp STRING;
DECLARE opt_strategy STRING;
DECLARE query STRING;
DECLARE flag BOOL;

/*
-- 1. Check input params

-- 2. Check input data
All facilities-dpoints pairs are in costs

-- 3. Run Location-Allocation. 
Extract constraints data if compatibility_bool
Remove competitors (always) and dpoints captured by competitors (if competitor_facilities_bool)

-- 4. Extract output 
(what happens if it fails?)
*/

BEGIN

    SET output_table_temp = CONCAT(REPLACE(output_table, '`', ''), "_temp");

    -- 1. Check input params
    -- No checks needed, data was checked using 'Prepare x' components. 
    -- If there are NULLs in input columns, an error will occurr when calling LOCATION_ALLOCATION
    -- and we avoid doing intensive checks

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
        FULL OUTER JOIN (
            SELECT facility_id, dpoint_id
            FROM `%s` CROSS JOIN `%s`
        ) t2
        ON t1.facility_id = t2.facility_id AND t1.dpoint_id = t2.dpoint_id
    """,
    REPLACE(costs_table, '`', ''),
    REPLACE(facilities_table, '`', ''),
    REPLACE(dpoints_table, '`', '')
    );
    EXECUTE IMMEDIATE query INTO flag;
    IF flag THEN
        RAISE USING MESSAGE = 'Missing costs detected. Please assign one cost for each facility-demand point pair.';
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
        c_compatibility AS (
            SELECT
                ARRAY_AGG(CAST(c.facility_id AS STRING)) compatibility_facility_id,
                ARRAY_AGG(CAST(c.dpoint_id AS STRING)) compatibility_dpoint_id,
                ARRAY_AGG(CAST(c.compatibility AS INT64)) compatibility_type
            FROM `%s` c
            INNER JOIN facilities_comp f USING (facility_id)                     -- remove competitors
            LEFT JOIN dpoints_comp d ON c.dpoint_id = d.dpoint_id 
            WHERE d.dpoint_id IS NULL                                     -- remove dpoints captured by competitors
        ),
        ''',
        REPLACE(c_compatibility_table, '`', '')
        );

        SET c_compatibility_join = "CROSS JOIN c_compatibility";
    END IF;

    EXECUTE IMMEDIATE FORMAT('''
    CREATE OR REPLACE TABLE `%s` AS
    WITH 
    dpoints_comp AS (
        -- Customers captured by competitors
        SELECT DISTINCT c.dpoint_id
        FROM `%s` c
        JOIN `%s` f 
        ON c.facility_id = f.facility_id
        WHERE f.facility_type = 2 AND c.cost <= %f
    ),
    facilities_comp AS (
        SELECT 
            facility_id,
            facility_type,
            %s AS facility_group_id,                                    -- make sure this variables are informed 
            %s AS facility_min_capacity,                                -- (if any NULL, internal error)
            %s AS facility_max_capacity,
            %s AS facility_cost_of_open
        FROM `%s` 
        WHERE facility_type != 2                                        -- remove competitors
    ),
    facilities AS (
        SELECT 
            ARRAY_AGG(CAST(facility_id AS STRING)) facility_id,
            ARRAY_AGG(CAST(facility_type AS INT64)) facility_type,
            ARRAY_AGG(CAST(facility_group_id AS STRING)) facility_group_id,                            
            ARRAY_AGG(CAST(facility_min_capacity AS FLOAT64)) facility_min_capacity,                       
            ARRAY_AGG(CAST(facility_max_capacity AS FLOAT64)) facility_max_capacity,
            ARRAY_AGG(CAST(facility_cost_of_open AS FLOAT64)) facility_cost_of_open
        FROM facilities_comp
    ),
    dpoints AS (
        SELECT
            ARRAY_AGG(CAST(c.dpoint_id AS STRING)) dpoint_id,
            ARRAY_AGG(CAST(%s AS FLOAT64)) dpoint_demand
        FROM `%s` c
        LEFT JOIN dpoints_comp d ON c.dpoint_id = d.dpoint_id 
        WHERE d.dpoint_id IS NULL                                             -- remove dpoints captured by competitors
    ),
    costs AS (
        SELECT 
            ARRAY_AGG(CAST(c.facility_id AS STRING)) cost_facility_id,
            ARRAY_AGG(CAST(c.dpoint_id AS STRING)) cost_dpoint_id,
            ARRAY_AGG(CAST(c.cost AS FLOAT64)) cost
        FROM `%s` c
        INNER JOIN facilities_comp f USING (facility_id)                        -- remove competitors
        LEFT JOIN dpoints_comp d ON c.dpoint_id = d.dpoint_id 
        WHERE d.dpoint_id IS NULL                                             -- remove dpoints captured by competitors
    ),
    %s
    result AS (
    SELECT  *
    FROM facilities CROSS JOIN dpoints CROSS JOIN costs %s
    )
    SELECT s.facility_id, s.customer_id as dpoint_id, s.demand, s.objective_value, s.gap, s.solving_time, s.termination_reason, s.stats
    FROM result, UNNEST(@@workflows_temp@@.`LOCATION_ALLOCATION`
    (    
        '%s',
        facility_id,
        facility_type,
        facility_group_id,
        facility_min_capacity,
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
        %d,
        %d,
        False
    )) s
    ''',
    output_table_temp,
    -- competitors
    REPLACE(costs_table, '`', ''),
    REPLACE(facilities_table, '`', ''),
    IF(competitor_facilities_bool, competitor_trade_area, -1),
    -- facilities
    IF(limit_facilities_group_bool, 'group_id', 'COALESCE(group_id,"0")'),
    IF(facilities_min_capacity_bool, 'min_capacity', 'COALESCE(min_capacity,0)'),
    IF(facilities_max_capacity_bool, 'max_capacity', 'COALESCE(max_capacity,0)'),
    IF(costopen_facilities_bool, 'cost_of_open', 'COALESCE(cost_of_open,0)'),
    REPLACE(facilities_table, '`', ''),
    -- dpoints
    IF(demand_bool, 'c.demand', 'COALESCE(c.demand,0)'),
    REPLACE(dpoints_table, '`', ''),
    -- costs
    REPLACE(costs_table, '`', ''),
    -- constraints
    c_compatibility_query,
    c_compatibility_join,
    -- location allocation
    opt_strategy,
    IF(compatibility_bool, 'compatibility_facility_id', 'NULL'),
    IF(compatibility_bool, 'compatibility_dpoint_id', 'NULL'),
    IF(compatibility_bool, 'compatibility_type', 'NULL'),
    required_facilities_bool, 
    IF(limit_facilities_bool, CAST(max_facilities AS STRING), 'NULL'), 
    IF(limit_facilities_group_bool, CAST(max_facilities_group AS STRING), 'NULL'), 
    facilities_min_capacity_bool,
    facilities_max_capacity_bool,
    compatibility_bool,
    demand_bool,
    costopen_facilities_bool,
    IFNULL(coverage_radius,0),
    CAST(time_limit AS INT64),
    CAST(relative_gap AS INT64)
    );

    -- 4. Extract output
    EXECUTE IMMEDIATE FORMAT('''
    CREATE TABLE IF NOT EXISTS `%s` 
    OPTIONS (expiration_timestamp = TIMESTAMP_ADD(CURRENT_TIMESTAMP(), INTERVAL 30 DAY)) 
    AS
        SELECT facility_id, dpoint_id, demand, ST_MAKELINE(f.geom, c.geom) geom
        FROM `%s`
        JOIN  (SELECT facility_id, geom FROM `%s`) f
        USING (facility_id)
        JOIN   (SELECT dpoint_id, geom FROM `%s`) c
        USING (dpoint_id)
    ''',
    REPLACE(output_table, '`', ''),
    output_table_temp,
    REPLACE(facilities_table, '`', ''),
    REPLACE(dpoints_table, '`', '')
    );

    EXECUTE IMMEDIATE FORMAT('''
    CREATE TABLE IF NOT EXISTS `%s` 
    OPTIONS (expiration_timestamp = TIMESTAMP_ADD(CURRENT_TIMESTAMP(), INTERVAL 30 DAY)) 
    AS
        SELECT objective_value, gap, solving_time, termination_reason, stats
        FROM `%s`
        ORDER BY termination_reason NULLS LAST
        LIMIT 1
    ''',
    REPLACE(metrics_table, '`', ''),
    output_table_temp
    );

    EXECUTE IMMEDIATE FORMAT('''
    DROP TABLE `%s`;
    ''',
    output_table_temp
    );

END;