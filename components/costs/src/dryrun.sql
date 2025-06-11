EXECUTE IMMEDIATE FORMAT('''
CREATE TABLE IF NOT EXISTS `%s` (
facility_id STRING,
customer_id STRING,
cost FLOAT64
)
OPTIONS (
expiration_timestamp = TIMESTAMP_ADD(CURRENT_TIMESTAMP(), INTERVAL 30 DAY)
);
''', REPLACE(output_table, '`', ''));