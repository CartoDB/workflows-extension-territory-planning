CREATE OR REPLACE FUNCTION `cartobq.us._territory_balancing`(
        geoid_column JSON,
        demand_column JSON,
        score_column JSON,
        nparts INT64,
        tolerance FLOAT64,
        grid_type STRING
    ) RETURNS JSON 
    REMOTE WITH CONNECTION `cartobq.us.remote-bigfunctions`  
    OPTIONS( max_batching_rows = 1, endpoint = 'https://territory-balancing-75xvxpwxma-uc.a.run.app')