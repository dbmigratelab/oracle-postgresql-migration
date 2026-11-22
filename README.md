# Oracle PostgreSQL Migration

**Copyright © 2026 Josselin Joly – DBMigrateLab**

Ansible-based orchestration of Oracle to PostgreSQL migrations using Ora2Pg.

The project is inspired by two shell-based migration scripts, one designed for production and the other for non-production environments. These scripts cover reporting, object export, COPY data loading and validation checks.

This project does not execute those scripts and does not inherit their dependencies on the Oracle database repository.

## Prerequisites

- Ansible installed on the control node; SSH access to **a single server** in the `migration_servers` group for each execution.
- On that server: Ora2Pg, Perl, DBD::Oracle, DBD::Pg and the `psql` client; a working Oracle client and Oracle environment. For assessment only, DBD::Pg and `psql` are not required.
- PostgreSQL database and users already created, Oracle privileges to read source objects and data, and PostgreSQL privileges required for object creation and COPY operations.
- Tested backups and a validated restoration procedure. The project does not automatically drop or recreate databases or roles.

Configure the inventory file `inventories/dev/hosts.yml`, `inventories/recette/hosts.yml` or `inventories/production/hosts.yml`, and set the parameters in `vars/migration.yml`.

Inventory values are examples and must be replaced with your actual environment settings. Variables defined in `vars/migration.yml` are loaded through `vars_files` and take precedence over inventory variables. Use additional variables (`-e`) to override settings for a specific execution or environment.

Passwords must be stored in Ansible Vault, outside the repository, and provided through an additional variables file. For example:

```bash
cd oracle-postgresql-migration
ansible-vault create /secure/path/migration-vault.yml
```

Enter the following content in the encrypted file, using your actual credentials:

```yaml
oracle_password: "oracle_password"
postgres_password: "postgresql_password"
```

Variables can also be provided through an encrypted variables file dedicated to each environment.

Never pass passwords in plain text on the command line.

The Ora2Pg configuration file deployed on the migration server contains credentials in plain text. It is stored in a directory with `0700` permissions and file permissions set to `0600`. Access must be restricted to the execution account, and configuration files must be removed after use according to the local security policy.

Reports and exports may contain sensitive data. Relevant tasks use `no_log` to prevent sensitive information from appearing in Ansible output.

## Configuration Parameters

| Variable | Description |
| --- | --- |
| `oracle_host`, `oracle_port`, `oracle_service` | Oracle source connection; default port `1521` |
| `oracle_user`, `oracle_password` | Oracle read-only account credentials |
| `oracle_schema` | Single source schema, used when `oracle_schemas` is not provided |
| `oracle_schemas` | List of source schemas, e.g. `[SCHEMA_CLIENT, SCHEMA_COMPTA, SCHEMA_RH]` |
| `postgres_host`, `postgres_port`, `postgres_db` | PostgreSQL target connection; default port `5432` |
| `postgres_user`, `postgres_password` | PostgreSQL migration account credentials |
| `postgres_schema_map` | Mapping dictionary from Oracle schemas to PostgreSQL schemas; otherwise, Oracle schema names are converted to lowercase |
| `migration_type` | Migration mode: `FULL` by default, `SCHEMA`, `DATA` or `ASSESSMENT` |
| `migration_home` | Remote working directory; defaults to `/opt/oracle-postgresql-migration` |
| `migration_become` | Ansible privilege escalation, enabled by default; disable it if the remote account can write to `migration_home` |
| `ora2pg_install_packages`, `ora2pg_packages` | Optional installation of distribution-specific packages; disabled by default |

`postgres_schema_map` can be partial, for example:

```yaml
postgres_schema_map:
  SCHEMA_CLIENT: client
```

Schemas not explicitly mapped use their source names converted to lowercase.

Target schema names must be valid, simple lowercase PostgreSQL identifiers and must be unique.

Passwords and DSN fields must not contain newline characters.

Hostnames, service names, database names and usernames are intentionally restricted to simple characters.

## Execution

From the project root directory, adjust the inventory and file paths to match your environment:

```bash
ansible-playbook -i inventories/dev/hosts.yml playbooks/precheck.yml -e @/secure/path/migration-vault.yml --ask-vault-pass

ansible-playbook -i inventories/dev/hosts.yml playbooks/migration.yml -e @/secure/path/migration-vault.yml --ask-vault-pass

ansible-playbook -i inventories/recette/hosts.yml playbooks/assessment.yml -e @/secure/path/migration-vault.yml --ask-vault-pass

ansible-playbook -i inventories/production/hosts.yml playbooks/schema_migration.yml -e @/secure/path/migration-vault.yml --ask-vault-pass

ansible-playbook -i inventories/production/hosts.yml playbooks/data_migration.yml -e @/secure/path/migration-vault.yml --ask-vault-pass

ansible-playbook -i inventories/production/hosts.yml playbooks/validation.yml -e @/secure/path/migration-vault.yml --ask-vault-pass
```

When using `playbooks/migration.yml`, select the migration mode with one of the following options:

- `-e migration_type=ASSESSMENT`
- `-e migration_type=SCHEMA`
- `-e migration_type=DATA`
- `-e migration_type=FULL`

Specialized playbooks define their own default migration mode. An additional `migration_type` variable overrides that default.

`precheck.yml` uses the selected mode to determine which checks to perform.

For an assessment without a PostgreSQL target, use `assessment.yml` or:

```bash
precheck.yml -e migration_type=ASSESSMENT
```

### Migration Modes

| Mode | Behavior |
| --- | --- |
| `ASSESSMENT` | `SHOW_TABLE`, `SHOW_COLUMN` and `SHOW_REPORT` only; no PostgreSQL access |
| `SCHEMA` | Object export and application; no `COPY` operations |
| `DATA` | `COPY` into existing tables; no schema or object creation |
| `FULL` | Reports, schema export and application, `COPY`, indexes and constraints, followed by remaining objects |

Exports and reports are stored on the remote server under:

```text
migration_home/<schema>/
```

Schema exports are isolated by execution.

`TEST_COUNT` results and PostgreSQL row counts are recorded in `reports/` after `DATA` or `FULL` executions.

`SCHEMA` only produces PostgreSQL row counts.

Review and compare the results carefully: a successful return code does not guarantee data equality or functional compatibility.

**Important considerations:**

- `DATA` inserts data without emptying the target tables (`TRUNCATE_TABLE 0`).
- Re-running a `DATA` migration may create duplicate records or fail because of existing constraints.
- `DATA` is not an incremental synchronization mechanism.
- `FULL` and `SCHEMA` are not idempotent. A failure may leave partially applied objects or data.
- Sequences are not resynchronized by `DATA` alone.

Refer to the [migration procedure](docs/migration_procedure.md) before execution.

## Local Tests

The following command runs the local smoke tests:

```bash
bash tests/smoke.sh
```

These tests use Ansible and simulated commands to verify orchestration behavior.

They do not replace a full validation in an environment running Oracle, PostgreSQL and the same Ora2Pg version as the target production environment.

## License

This project is licensed under the Apache License, Version 2.0.

See the [LICENSE](LICENSE) file for details.

---

## Author, Copyright & Maintainer

**Created and maintained by Josselin Joly**

Database Administrator & Migration Expert  
Oracle / PostgreSQL

**Project:** DBMigrateLab – Oracle to PostgreSQL Migration Framework

**Copyright © 2026 Josselin Joly. All rights reserved.**

GitHub: [DBMigrateLab](https://github.com/dbmigratelab)  
Website: [Data Admin Pro](https://data-adminpro.fr)

This project is an original work developed by Josselin Joly, based on professional experience in Oracle and PostgreSQL database administration and migration.

Licensed under the Apache License, Version 2.0. See [LICENSE](LICENSE) for details.

---

[English](README.md) | [Français](README.fr.md)
