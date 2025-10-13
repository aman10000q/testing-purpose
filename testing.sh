#!/bin/bash
set -euo pipefail

echo "Testing the Database Connection..."
PGPASSWORD=$PGPASSWORD psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER_NAME" -d orchestrator -t -c "SELECT * FROM schema_migrations;"
echo "Connection done"

# Migration configs
declare -A orchMigrationConfig=(
  [repoUrl]="devtron-labs/devtron-enterprise"
  [branch]="$orchBranch"
  [directory]="scripts/sql"
  [cloneDir]="orch"
)
declare -A casbinMigrationConfig=(
  [repoUrl]="devtron-labs/devtron-enterprise"
  [branch]="$casbinBranch"
  [directory]="scripts/casbin"
  [cloneDir]="casbin"
)
declare -A gitSensorMigrationConfig=(
  [repoUrl]="devtron-labs/devtron-services-enterprise"
  [branch]="$gitSensorBranch"
  [directory]="git-sensor/scripts/sql"
  [cloneDir]="git"
)
declare -A lensMigrationConfig=(
  [repoUrl]="devtron-labs/lens"
  [branch]="$lensBranch"
  [directory]="scripts/sql"
  [cloneDir]="lens"
)

migrationConfigs=(orchMigrationConfig casbinMigrationConfig gitSensorMigrationConfig lensMigrationConfig)

# Loop through configs
for configName in "${migrationConfigs[@]}"; do
  declare -n currentConfig="$configName"

  echo "===================================================="
  echo "🔧 Checking migrations for ${currentConfig[cloneDir]}"
  echo "Repo: ${currentConfig[repoUrl]}"
  echo "Branch: ${currentConfig[branch]}"
  echo "===================================================="

  # Directories for cloning
  sourceDir="testing-${currentConfig[cloneDir]}-$sourceOfTruth"
  targetDir="testing-${currentConfig[cloneDir]}-${currentConfig[branch]}"
  
  repoUrl="https://$GIT_TOKEN@github.com/${currentConfig[repoUrl]}"

  # Clone source-of-truth branch
  echo "Cloning $repoUrl branch $sourceOfTruth into $sourceDir"
  git clone --depth 1 "$repoUrl" -b "$sourceOfTruth" "$sourceDir"

  # Clone target branch
  echo "Cloning $repoUrl branch ${currentConfig[branch]} into $targetDir"
  git clone --depth 1 "$repoUrl" -b "${currentConfig[branch]}" "$targetDir"

  # Get migration files
  pushd "$sourceDir/${currentConfig[directory]}" > /dev/null
  mapfile -t sourceMigrations < <(ls -1 | grep -E '^[0-9]+' | sort)
  popd > /dev/null

  pushd "$targetDir/${currentConfig[directory]}" > /dev/null
  mapfile -t targetMigrations < <(ls -1 | grep -E '^[0-9]+' | sort)
  popd > /dev/null

  # Determine migrations to run down
  migrationsToRunDown=()
  for mig in "${targetMigrations[@]}"; do
    if [[ ! " ${sourceMigrations[*]} " =~ " $mig " ]]; then
      migrationsToRunDown+=("$mig")
    fi
  done

  echo "${currentConfig[cloneDir]}: Migrations to run down count: ${#migrationsToRunDown[@]}"
  if [[ ${#migrationsToRunDown[@]} -gt 0 ]]; then
    echo "Migration versions to run down: ${migrationsToRunDown[*]}"
    
    pushd "$targetDir/${currentConfig[directory]}" > /dev/null
    for mig in "${migrationsToRunDown[@]}"; do
      echo "Running down migration: $mig"
      migrate -path . -database "postgres://$DB_USER_NAME:$PGPASSWORD@$DB_HOST:$DB_PORT/orchestrator?sslmode=disable" down
    done
    popd > /dev/null
  else
    echo "No migrations to run down for ${currentConfig[cloneDir]}"
  fi

done
