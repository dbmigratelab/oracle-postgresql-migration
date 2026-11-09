# Oracle PostgreSQL Migration

Orchestration Ansible de migrations Oracle vers PostgreSQL avec Ora2Pg. Le
projet s'inspire de deux scripts shell de migration, l'un pour la production et l'autre pour la hors production : rapports,
export des objets, chargement COPY et controles. Il ne lance pas ces scripts et
ne reprend pas leurs dependances au referentiel de la base oracle.

## Avant de commencer

- Ansible sur le poste de controle ; acces SSH a **un seul** serveur du groupe
  `migration_servers` pour une execution donnee.
- Sur ce serveur : Ora2Pg, Perl, DBD::Oracle, DBD::Pg et le client `psql` ;
  client Oracle et environnement Oracle fonctionnels. Pour l'analyse seule,
  DBD::Pg et `psql` ne sont pas requis.
- Base PostgreSQL et utilisateurs deja crees, privileges Oracle de lecture des
  objets et donnees, privileges PostgreSQL necessaires a la creation et au COPY.
- Sauvegardes et procedure de restauration testees. Pas de suppression ni de
  recreation automatique de la base ou des roles.

Renseigner l'inventaire `inventories/dev/hosts.yml`,
`inventories/recette/hosts.yml` ou `inventories/production/hosts.yml` et les
parametres dans `vars/migration.yml`. Les valeurs des inventaires sont des
exemples a remplacer. Les valeurs de `vars/migration.yml` sont chargees comme
`vars_files` et priment sur les variables de l'inventaire ; utiliser des
variables supplementaires (`-e`) pour une execution ou un environnement.

Les mots de passe doivent etre stockes dans Ansible Vault, hors du depot, et
fournis via un fichier de variables supplementaires. Par exemple :

```bash
cd oracle-postgresql-migration
ansible-vault create /chemin/securise/migration-vault.yml
```

Contenu a saisir dans le fichier chiffre, avec les vraies valeurs :

```yaml
oracle_password: "mot_de_passe_oracle"
postgres_password: "mot_de_passe_postgresql"
```

Les variables peuvent aussi etre passees dans un fichier de variables chiffre
par environnement. Ne jamais les passer en clair sur la ligne de commande.
Le fichier Ora2Pg deploye contient les secrets en clair sur le serveur de
migration, dans un repertoire `0700` avec des droits `0600` : restreindre
l'acces au compte d'execution et supprimer les configurations selon la politique
locale apres usage. Les rapports et exports peuvent contenir des donnees
sensibles. Les taches concernées utilisent `no_log`.

## Parametres

| Variable | Description |
| --- | --- |
| `oracle_host`, `oracle_port`, `oracle_service` | Connexion source ; port par defaut `1521` |
| `oracle_user`, `oracle_password` | Compte Oracle de lecture |
| `oracle_schema` | Schema source unique, si `oracle_schemas` n'est pas fourni |
| `oracle_schemas` | Liste des schemas source, par exemple `[SCHEMA_CLIENT, SCHEMA_COMPTA, SCHEMA_RH]` |
| `postgres_host`, `postgres_port`, `postgres_db` | Connexion cible ; port par defaut `5432` |
| `postgres_user`, `postgres_password` | Compte PostgreSQL de migration |
| `postgres_schema_map` | Dictionnaire schema Oracle vers schema PostgreSQL ; sinon nom Oracle en minuscules |
| `migration_type` | `FULL` par defaut, `SCHEMA`, `DATA` ou `ASSESSMENT` |
| `migration_home` | Repertoire de travail distant, par defaut `/opt/oracle-postgresql-migration` |
| `migration_become` | Elevation Ansible, activee par defaut ; desactiver si le compte distant peut ecrire dans `migration_home` |
| `ora2pg_install_packages`, `ora2pg_packages` | Installation optionnelle des paquets adaptes a la distribution ; desactivee par defaut |

`postgres_schema_map` peut etre partiel, par exemple
`{SCHEMA_CLIENT: client}` ; les autres schemas utilisent leur nom source en
minuscules. Les noms cibles doivent etre des identifiants PostgreSQL simples en
minuscules et uniques. Les secrets et les champs de DSN ne doivent pas contenir
de retour a la ligne. Les noms d'hote, service, base et utilisateur sont
volontairement limites a des caracteres simples.

## Execution

Depuis la racine du projet, en adaptant les chemins et l'inventaire :

```bash
ansible-playbook -i inventories/dev/hosts.yml playbooks/precheck.yml -e @/chemin/securise/migration-vault.yml --ask-vault-pass
ansible-playbook -i inventories/dev/hosts.yml playbooks/migration.yml -e @/chemin/securise/migration-vault.yml --ask-vault-pass
ansible-playbook -i inventories/recette/hosts.yml playbooks/assessment.yml -e @/chemin/securise/migration-vault.yml --ask-vault-pass
ansible-playbook -i inventories/production/hosts.yml playbooks/schema_migration.yml -e @/chemin/securise/migration-vault.yml --ask-vault-pass
ansible-playbook -i inventories/production/hosts.yml playbooks/data_migration.yml -e @/chemin/securise/migration-vault.yml --ask-vault-pass
ansible-playbook -i inventories/production/hosts.yml playbooks/validation.yml -e @/chemin/securise/migration-vault.yml --ask-vault-pass
```

Avec `playbooks/migration.yml`, choisir un mode au moyen de
`-e migration_type=ASSESSMENT`, `SCHEMA`, `DATA` ou `FULL`. Les playbooks
specialises fixent leur mode par defaut ; une variable supplementaire
`migration_type` le remplace. `precheck.yml` utilise le mode choisi pour ses
controles. Pour une analyse sans cible PostgreSQL, utiliser `assessment.yml` ou
`precheck.yml -e migration_type=ASSESSMENT`.

| Mode | Comportement |
| --- | --- |
| `ASSESSMENT` | `SHOW_TABLE`, `SHOW_COLUMN`, `SHOW_REPORT` uniquement, sans acces PostgreSQL |
| `SCHEMA` | Export et application des objets ; aucun `COPY` |
| `DATA` | `COPY` vers les tables existantes ; aucune creation de schema ou objet |
| `FULL` | Rapports, export et application du schema, `COPY`, index et contraintes, puis objets restants |

Les exports et rapports sont conserves sous `migration_home/<schema>/` sur le
serveur distant. Les exports de schema sont isoles par execution. `TEST_COUNT`
et les comptages PostgreSQL sont enregistres dans `reports/` apres `DATA` ou
`FULL` ; `SCHEMA` produit les comptages PostgreSQL uniquement. Consulter et
comparer les resultats : un code retour nul ne certifie pas l'egalite des
donnees ni la compatibilite fonctionnelle.

**Attention :** `DATA` ajoute les donnees sans vider la cible (`TRUNCATE_TABLE 0`).
Une relance peut creer des doublons ou echouer sur des contraintes. Ce n'est pas
une synchronisation incrementale. `FULL` et `SCHEMA` ne sont pas idempotents :
un echec peut laisser des objets ou des donnees partiellement appliques. Les
sequences ne sont pas resynchronisees par `DATA` seul. Voir
[la procedure](docs/migration_procedure.md) avant execution.

## Tests locaux

`bash tests/smoke.sh` utilise Ansible et des commandes simulees. Ces tests
verifient l'orchestration mais ne remplacent pas une recette sur Oracle,
PostgreSQL et la version d'Ora2Pg utilisee en exploitation.
