EXECUTE IMMEDIATE FORMAT('''
CREATE TABLE IF NOT EXISTS `%s` (
facility_id STRING,
dpoint_id STRING,
demand FLOAT64,
geom GEOGRAPHY
)
OPTIONS (
expiration_timestamp = TIMESTAMP_ADD(CURRENT_TIMESTAMP(), INTERVAL 30 DAY)
);
''', REPLACE(output_table, '`', ''));

EXECUTE IMMEDIATE FORMAT('''
CREATE TABLE IF NOT EXISTS `%s` (
objective_value FLOAT64,
gap FLOAT64,
solving_time FLOAT64,
termination_reason STRING,
stats STRING
)
OPTIONS (
expiration_timestamp = TIMESTAMP_ADD(CURRENT_TIMESTAMP(), INTERVAL 30 DAY)
);
''', REPLACE(metrics_table, '`', ''));