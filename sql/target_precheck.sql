SELECT count(*)
FROM information_schema.tables
WHERE table_schema = :'target_schema' AND table_type = 'BASE TABLE';
