SELECT format('SELECT %L AS table_name, count(*) AS row_count FROM %I.%I;',
              table_name, table_schema, table_name)
FROM information_schema.tables
WHERE table_schema = :'target_schema' AND table_type = 'BASE TABLE'
ORDER BY table_name
\gexec
