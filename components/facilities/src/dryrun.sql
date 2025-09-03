EXECUTE IMMEDIATE FORMAT('''
CREATE TABLE IF NOT EXISTS `%s` (
facility_id STRING,
geom GEOGRAPHY,
facility_type INT64,
group_id STRING,
min_usage FLOAT64,
max_capacity FLOAT64,
cost_of_open FLOAT64
)
OPTIONS (
expiration_timestamp = TIMESTAMP_ADD(CURRENT_TIMESTAMP(), INTERVAL 30 DAY)
);
''', REPLACE(output_table, '`', ''));