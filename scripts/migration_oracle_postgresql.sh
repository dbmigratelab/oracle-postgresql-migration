#!/usr/bin/env bash
set -euo pipefail
umask 077
if [[ $# -ne 2 ]]; then
echo "Usage: $0 SCHEMA_ORACLE FULL|SCHEMA|DATA|ASSESSMENT" >&2
exit 2
fi
schema=$1
mode=$2
[[ $schema =~ ^[A-Za-z][A-Za-z0-9_$#]$ ]] || { echo "Schema Oracle invalide" >&2; exit 2; }
case "$mode" in FULL|SCHEMA|DATA|ASSESSMENT) ;; ) echo "Mode invalide: $mode" >&2; exit 2 ;; esac
: "${MIGRATION_HOME:?MIGRATION_HOME requis}"
if [[ $mode != ASSESSMENT ]]; then
: "${PGHOST:?PGHOST requis}" "${PGPORT:?PGPORT requis}" "${PGDATABASE:?PGDATABASE requis}" "${PGUSER:?PGUSER requis}" "${TARGET_SCHEMA:?TARGET_SCHEMA requis}"
fi
project="${MIGRATION_HOME}/${schema}"
conf="${project}/ora2pg.conf"
[[ -r $conf ]] || { echo "Configuration introuvable: $conf" >&2; exit 1; }
mkdir -p "$project/reports" "$project/schema"
run_sql() {
local file=$1
if [[ -s $file ]]; then
psql -X -v ON_ERROR_STOP=1 -f "$file"
fi
}
assessment() {
ora2pg -c "$conf" -t SHOW_TABLE > "$project/reports/tables.txt"
ora2pg -c "$conf" -t SHOW_COLUMN > "$project/reports/columns.txt"
ora2pg -c "$conf" -t SHOW_REPORT --dump_as_html --estimate_cost > "$project/reports/assessment.html"
}
export_schema() {
local type
export_dir=$(mktemp -d "$project/schema/run.XXXXXXXX")
for type in TYPE SEQUENCE TABLE FUNCTION PROCEDURE PACKAGE VIEW MVIEW TRIGGER PARTITION TABLESPACE DBLINK SYNONYM DIRECTORY GRANT SEQUENCE_VALUES; do
mkdir -p "$export_dir/$type"
ora2pg -p -c "$conf" -t "$type" -o "${type}.sql" -b "$export_dir/$type"
done
}
apply_base_schema() {
local type package_file
psql -X -v ON_ERROR_STOP=1 -v "target_schema=$TARGET_SCHEMA" -f "$MIGRATION_HOME/sql/prepare.sql"
for type in TYPE SEQUENCE TABLE FUNCTION PROCEDURE; do
run_sql "$export_dir/$type/${type}.sql"
done
run_sql "$export_dir/PACKAGE/PACKAGE.sql"
for package_file in "$export_dir/PACKAGE/"_PACKAGE.sql; do
run_sql "$package_file"
done
}
apply_remaining_schema() {
local type
for type in VIEW MVIEW TRIGGER PARTITION TABLESPACE DBLINK SYNONYM DIRECTORY GRANT SEQUENCE_VALUES; do
run_sql "$export_dir/$type/${type}.sql"
done
run_sql "$export_dir/TABLESPACE/TBSP_INDEXES_TABLESPACE.sql"
}
apply_constraints() {
local prefix
for prefix in INDEXES CONSTRAINTS FKEYS; do
run_sql "$export_dir/TABLE/${prefix}_TABLE.sql"
done
}
copy_data() {
ora2pg -c "$conf" -t COPY
}
case "$mode" in
ASSESSMENT) assessment ;;
SCHEMA) export_schema; apply_base_schema; apply_constraints; apply_remaining_schema ;;
DATA) copy_data ;;
FULL) assessment; export_schema; apply_base_schema; copy_data; apply_constraints; apply_remaining_schema ;;
esac