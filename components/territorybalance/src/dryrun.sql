EXECUTE IMMEDIATE FORMAT(
    '''
    CREATE TABLE IF NOT EXISTS
        `%s`
    OPTIONS(
        expiration_timestamp = TIMESTAMP_ADD(CURRENT_TIMESTAMP(), INTERVAL 30 DAY)
    )
    AS SELECT
        %s,
        0 AS cluster
    FROM
        `%s` input
    WHERE 1 = 0;
    ''',
    REPLACE(output_table, '`', ''),
    IF(keep_input_columns, 'input.*', FORMAT('input.%s', index_column)),
    REPLACE(input_table, '`', '')
);