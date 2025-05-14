EXECUTE IMMEDIATE FORMAT(
    '''
    CREATE TABLE IF NOT EXISTS
        `%s`
    OPTIONS(
        expiration_timestamp = TIMESTAMP_ADD(CURRENT_TIMESTAMP(), INTERVAL 30 DAY)
    )
    AS SELECT
        input.%s,
        0 AS node,
        0.0 AS demand,
        0.0 AS score,
        0 AS cluster %s
    FROM
        `%s` input
    WHERE 1 = 0;
    ''',
    output_table,
    index_column,
    IF(keep_input_columns, FORMAT(', input.*EXCEPT(%s)', index_column), ''),
    input_table
);