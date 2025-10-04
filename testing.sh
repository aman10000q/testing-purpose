#!/bin/bash
set -e

echo "Testing the Database Connection:"
PGPASSWORD=$PGPASSWORD psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER_NAME" -d orchestrator -t -c "SELECT * FROM schema_migrations;"
echo "Connection done"

# Define migration configs
declare -A orchMigrationConfig=(
  [repoUrl]="devtron-labs/devtron-enterprise"
  [branch]="$orchBranch"
  [directory]="scripts/sql"
  [cloneDir]="orch"
  [migToRunDown]=0
)

declare -A casbinMigrationConfig=(
  [repoUrl]="devtron-labs/devtron-enterprise"
  [branch]="$casbinBranch"
  [directory]="scripts/casbin"
  [cloneDir]="casbin"
  [migToRunDown]=0
)

declare -A gitSensorMigrationConfig=(
  [repoUrl]="devtron-labs/devtron-services-enterprise"
  [branch]="$gitSensorBranch"
  [directory]="git-sensor/scripts/sql"
  [cloneDir]="git"
  [migToRunDown]=0
)

declare -A lensMigrationConfig=(
  [repoUrl]="devtron-labs/lens"
  [branch]="$lensBranch"
  [directory]="scripts/sql"
  [cloneDir]="lens"
  [migToRunDown]=0
)

# Array of names of associative arrays
migrationConfigs=(orchMigrationConfig casbinMigrationConfig gitSensorMigrationConfig lensMigrationConfig)

# Loop through each config
for configName in "${migrationConfigs[@]}"; do
  declare -n currentConfig="$configName"

  sourceOfTruthLatestMigration=0
  targetLatestMigration=0

  for branch in "$sourceOfTruth" "${currentConfig[branch]}"; do
    directoryForCloning="testing-${currentConfig[cloneDir]}-$branch"
    repoUrl="https://$GIT_TOKEN@github.com/${currentConfig[repoUrl]}"

    echo "Cloning $repoUrl branch $branch into $directoryForCloning"
    git clone --depth 1 "$repoUrl" -b "$branch" "$directoryForCloning"

    pushd "$directoryForCloning/${currentConfig[directory]}" > /dev/null

    latestMigration=$(ls | grep -E '^[0-9]+' | sed -E 's/^([0-9]+).*/\1/' | sort -n | tail -1)

    if [[ "$branch" == "$sourceOfTruth" ]]; then
      sourceOfTruthLatestMigration=$latestMigration
    else
      targetLatestMigration=$latestMigration
      # Arithmetic must be outside double-parens when assigning
      currentConfig[migToRunDown]=$((targetLatestMigration - sourceOfTruthLatestMigration))
    fi

    popd > /dev/null
  done

  echo "${currentConfig[cloneDir]}: Migrations to run down: ${currentConfig[migToRunDown]}"
done


