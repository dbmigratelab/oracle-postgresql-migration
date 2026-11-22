#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
export PATH="$root/tests/mock_bin:$PATH"
export FAKE_LOG="$work/commands.log"
export ANSIBLE_CONFIG="$root/ansible.cfg"
vars="{\"migration_home\":\"$work/project\",\"migration_become\":false,\"oracle_host\":\"oracle.example\",\"oracle_service\":\"ORCL\",\"oracle_user\":\"reader\",\"oracle_password\":\"test\",\"oracle_schemas\":[\"APP\"],\"postgres_host\":\"postgres.example\",\"postgres_db\":\"migration\",\"postgres_user\":\"writer\",\"postgres_password\":\"test\"}"

direct_project="$work/direct"
mkdir -p "$direct_project"
printf -v schema_63 'A%062d' 0
printf -v schema_64 'A%063d' 0
for schema in ALEX APP SCHEMA_CLIENT 'A$B' 'A#B' "$schema_63"; do
    mkdir -p "$direct_project/$schema"
    : > "$direct_project/$schema/ora2pg.conf"
    MIGRATION_HOME="$direct_project" "$root/scripts/migration_oracle_postgresql.sh" "$schema" ASSESSMENT
done
for schema in "$schema_64" _INVALID 'A-B'; do
    if MIGRATION_HOME="$direct_project" "$root/scripts/migration_oracle_postgresql.sh" "$schema" ASSESSMENT > /dev/null 2>&1; then
        printf 'Schema Oracle invalide accepte: %s\n' "$schema" >&2
        exit 1
    fi
done
if MIGRATION_HOME="$direct_project" "$root/scripts/migration_oracle_postgresql.sh" APP INVALID > /dev/null 2>&1; then
    echo 'Mode invalide accepte' >&2
    exit 1
fi
printf 'validation directe du script: OK\n'

for mode in assessment schema_migration data_migration migration; do
    : > "$FAKE_LOG"
    ansible-playbook -i "$root/tests/inventory.yml" "$root/playbooks/$mode.yml" -e "$vars" > "$work/ansible.log" || { cat "$work/ansible.log"; exit 1; }
    case "$mode" in
        assessment)
            grep -q '^ora2pg SHOW_REPORT$' "$FAKE_LOG"
            ! grep -Eq '^psql |^ora2pg (COPY|TABLE)$' "$FAKE_LOG"
            ;;
        schema_migration)
            grep -q '^ora2pg TABLE$' "$FAKE_LOG"
            grep -q 'INDEXES_TABLE.sql' "$FAKE_LOG"
            grep -q 'sample_PACKAGE.sql' "$FAKE_LOG"
            ! grep -q '^ora2pg COPY$' "$FAKE_LOG"
            ;;
        data_migration)
            grep -q '^ora2pg COPY$' "$FAKE_LOG"
            ! grep -q '^ora2pg TABLE$' "$FAKE_LOG"
            ;;
        migration)
            grep -q '^ora2pg SHOW_REPORT$' "$FAKE_LOG"
            grep -q '^ora2pg COPY$' "$FAKE_LOG"
            copy_line=$(grep -n '^ora2pg COPY$' "$FAKE_LOG" | cut -d: -f1)
            index_line=$(grep -n 'INDEXES_TABLE.sql' "$FAKE_LOG" | cut -d: -f1)
            [[ $copy_line -lt $index_line ]]
            trigger_line=$(grep -n -- '-f .*/TRIGGER/TRIGGER.sql' "$FAKE_LOG" | cut -d: -f1)
            [[ $copy_line -lt $trigger_line ]]
            ;;
    esac
    printf '%s: OK\n' "$mode"
done

: > "$FAKE_LOG"
ansible-playbook -i "$root/tests/inventory.yml" "$root/playbooks/assessment.yml" -e "$vars" -e '{"postgres_host":"","postgres_db":"","postgres_user":"","postgres_password":""}' > "$work/ansible.log"
! grep -Eq '^psql |^ora2pg COPY$' "$FAKE_LOG"
printf 'assessment sans PostgreSQL: OK\n'

: > "$FAKE_LOG"
if FAKE_TARGET_COUNT=0 ansible-playbook -i "$root/tests/inventory.yml" "$root/playbooks/data_migration.yml" -e "$vars" > "$work/ansible.log"; then
    echo 'DATA doit refuser un schema cible sans table' >&2
    exit 1
fi
! grep -q '^ora2pg COPY$' "$FAKE_LOG"
printf 'DATA sans table cible: refuse\n'

: > "$FAKE_LOG"
if FAKE_FAIL_TYPE=COPY ansible-playbook -i "$root/tests/inventory.yml" "$root/playbooks/migration.yml" -e "$vars" > "$work/ansible.log"; then
    echo 'FULL doit echouer si COPY echoue' >&2
    exit 1
fi
! grep -q 'INDEXES_TABLE.sql' "$FAKE_LOG"
printf 'echec COPY: propage\n'

: > "$FAKE_LOG"
if ansible-playbook -i "$root/tests/inventory.yml" "$root/playbooks/migration.yml" -e "$vars" -e '{"oracle_schemas":["APP","OTHER"],"postgres_schema_map":{"OTHER":"app"}}' > "$work/ansible.log"; then
    echo 'Les schemas cibles identiques doivent etre refuses' >&2
    exit 1
fi
[[ ! -s $FAKE_LOG ]]
printf 'collision de schemas: refusee\n'