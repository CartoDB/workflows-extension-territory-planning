EXECUTE IMMEDIATE FORMAT('''
CREATE TABLE IF NOT EXISTS `%s` (
constraint_id STRING,
constraint_description STRING,
table_name STRING
)
OPTIONS (
expiration_timestamp = TIMESTAMP_ADD(CURRENT_TIMESTAMP(), INTERVAL 30 DAY)
);
''', REPLACE(output_table, '`', ''));