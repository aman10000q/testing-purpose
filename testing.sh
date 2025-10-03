#!/bin/bash
set -e

echo "Testing the Database Connection:"
PGPASSWORD=$PGPASSWORD psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER_NAME" -d orchestrator -t -c "SELECT * FROM schema_migrations;"
echo "Connection done"

# Clone repo
migrationsToRunDown=0
declare -A orchMigrationConfig
orchMigrationConfig[repoUrl]="/devtron-labs/devtron-enterprise"
orchMigrationConfig[branch]="$orchBranch"
orchMigrationConfig[directory]="/devtron-enterprise/scripts/sql"

declare -A casbinMigrationConfig
casbinMigrationConfig[repoUrl]="/devtron-labs/devtron-enterprise"
casbinMigrationConfig[branch]="${casbinBranch}"
casbinMigrationConfig[directory]="/devtron-enterprise/scripts/casbin"

declare -A gitSensorMigrationConfig
gitSensorMigrationConfig[repoUrl]="/devtron-labs/devtron-services-enterprise"
gitSensorMigrationConfig[branch]="${gitSensorBranch}"
gitSesnsorMigrationConfig[directory]="/devtron-enterprise/git-sensor/scripts/sql"

declare -A lensMigrationConfig
lensMigrationConfig[repoUrl]="/devtron-labs/lens"
lensMigrationConfig[branch]="${lensBranch}"
lensMigrationConfig[directory]="/lens/scripts/sql"

migrationConfigs=(orchMigrationConfig casbinMigrationConfig gitSensorMigrationConfig lensMigrationConfig);

for config in "{$migrationConfig[@]}"; do
  declare -n currentConfig="${config}"
  for 
  directoryForCloning="testing-$branch"
  git clone --depth 1 https://$GIT_TOKEN@github.com/devtron-labs/devtron-enterprise -b $branch "$directoryForCloning"
  









for branch in "${automationBranches[@]}"; do
  directoryForCloning="testing-$branch"
  git clone --depth 1 https://$GIT_TOKEN@github.com/devtron-labs/devtron-enterprise -b $branch "$directoryForCloning"
  cd "${directoryForCloning}/devtron-enterprise/scripts/sql"
  if [[ $branch=="$sourceOfTruth" ]]; then
    migrationsToRunDown=$(ls | grep -E '^[0-9]+' | sed -E 's/^([0-9]+).*/\1/' | sort -n | tail -1)
  else
    migrationsToRunDown=(($migrationsToRunDown-$(ls | grep -E '^[0-9]+' | sed -E 's/^([0-9]+).*/\1/' | sort -n | tail -1)))
  fi
done

echo "Highest migration in repo: $latest_migration"

