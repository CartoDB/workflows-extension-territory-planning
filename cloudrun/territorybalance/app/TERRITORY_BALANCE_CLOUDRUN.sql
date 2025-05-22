CREATE OR REPLACE FUNCTION `cartodb-on-gcp-datascience.lgarciaduarte.TERRITORY_BALANCE_CLOUDRUN`(
        geoid_column JSON,
        demand_column JSON,
        score_column JSON,
        nparts INT64,
        tolerance FLOAT64,
        grid_type STRING
    ) RETURNS JSON
    REMOTE WITH CONNECTION `cartodb-on-gcp-datascience.us.tb-connection`
    OPTIONS( max_batching_rows = 1, endpoint = 'https://territory-balancing-lgarciaduarte-267312430260.us-east1.run.app')