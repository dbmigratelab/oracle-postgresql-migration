# Procedure de migration

## 1. Preparation

1. Choisir un serveur de migration avec Ora2Pg et les clients Oracle et
   PostgreSQL compatibles ; verifier la connectivite et les privileges. Le
   playbook ne configure pas le client Oracle, le wallet ni les certificats TLS.
2. Identifier explicitement les schemas et leurs cibles, et creer la base et
   les comptes PostgreSQL. Prevoir les extensions, droits et tablespaces requis.
3. Configurer l'inventaire adapte, les variables et un fichier Ansible Vault.
   Prevoir le stockage et proteger les repertoires de rapports et d'exports.
4. Sauvegarder la cible, tester la restauration, definir la fenetre de
   migration et le plan de retour arriere. Desactiver ou coordonner les ecritures
   applicatives : chaque COPY est un chargement, pas une replication continue.
5. Executer `precheck.yml`. Pour `DATA`, le controle exige au moins une table
   cible par schema, mais ne verifie pas que toutes les tables ou leurs colonnes
   correspondent a la source.

## 2. Evaluation

Executer `assessment.yml` et examiner `reports/assessment.html`, `tables.txt`
et `columns.txt` pour chaque schema. Determiner les adaptations et les
dependances entre schemas avant toute application SQL.

## 3. Structure et donnees

- `schema_migration.yml` exporte puis applique les objets et contraintes sans
  transfert de donnees. Utiliser une cible preparee et examiner les erreurs.
- `data_migration.yml` charge dans des tables existantes, sans suppression ni
  deduplication. Preparer les tables, les contraintes et la strategie de reprise
  avant d'executer ; ce mode ne remet pas les sequences a niveau.
- `migration.yml -e migration_type=FULL` execute l'analyse, l'export, la
  structure de base, le COPY, les index et contraintes, puis les autres objets.

Les types, tables, sequences, fonctions, procedures, packages, vues, vues
materialisees, triggers, partitions, tablespaces, liens, synonymes, directories,
droits et valeurs de sequences sont demandes a Ora2Pg. Leur conversion et leur
ordre ne garantissent pas la compatibilite : packages, PL/SQL, extensions,
liens, privileges, objets inter-schemas et dependances peuvent exiger des
adaptations et une application manuelle. L'execution s'arrete a la premiere
erreur signalee par une commande ou par `psql` (`ON_ERROR_STOP`). Aucun retour
arriere automatique n'est effectue ; diagnostiquer l'etat partiel avant toute
reprise. Les nouveaux exports sont dans `schema/run.*` et ne reutilisent pas
les fichiers d'une execution precedente.

## 4. Validation et bascule

Executer `validation.yml` apres migration si necessaire. Examiner les resultats
Ora2Pg `TEST_COUNT` apres les modes `FULL` ou `DATA`, et les comptages exacts
PostgreSQL dans `reports/postgresql_counts.txt`. La comparaison des resultats,
les objets invalides, les valeurs des sequences et les tests fonctionnels sont
de la responsabilite de l'exploitant. Les resultats peuvent refleter des
modifications concurrentes : figer la source et la cible pendant les controles.
Effectuer les tests applicatifs, mettre a jour les statistiques PostgreSQL et
decider la bascule selon les criteres de recette etablis.

