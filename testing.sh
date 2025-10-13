#!/bin/bash
set -euo pipefail
echo "Testing the Database Connection..."
PGPASSWORD=$PGPASSWORD psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER_NAME" -d orchestrator -c "SELECT version, dirty FROM schema_migrations;"
echo "Connection done"

# ---------------- Migration configs ----------------
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

# migrationConfigs=(orchMigrationConfig casbinMigrationConfig gitSensorMigrationConfig lensMigrationConfig)
migrationConfigs=(orchMigrationConfig)

# ---------------- Migration processing ----------------
for configName in "${migrationConfigs[@]}"; do
  declare -n currentConfig="$configName"
  
  # Skip if source and target branch are same
  if [[ "$sourceOfTruth" == "${currentConfig[branch]}" ]]; then
    echo "Skipping ${currentConfig[cloneDir]} as branch is same as source-of-truth."
    continue
  fi
  
  echo "===================================================="
  echo "🔧 Checking migrations for ${currentConfig[cloneDir]}"
  echo "Repo: ${currentConfig[repoUrl]}"
  echo "Branch: ${currentConfig[branch]}"
  echo "===================================================="
  
  # Clone source-of-truth branch
  srcDir="testing-${currentConfig[cloneDir]}-$sourceOfTruth"
  echo "Cloning source-of-truth branch $sourceOfTruth into $srcDir"
  git clone --depth 1 "https://$GIT_TOKEN@github.com/${currentConfig[repoUrl]}" -b "$sourceOfTruth" "$srcDir"
  
  # Get latest migration number for source
  pushd "$srcDir/${currentConfig[directory]}" > /dev/null
  sourceLatestMigration=$(ls | grep -E '^[0-9]+' | sed -E 's/^([0-9]+).*/\1/' | sort -n | tail -1)
  popd > /dev/null
  echo "Source-of-truth latest migration: $sourceLatestMigration"
  
  # Clone target branch
  tgtDir="testing-${currentConfig[cloneDir]}-${currentConfig[branch]}"
  echo "Cloning target branch ${currentConfig[branch]} into $tgtDir"
  git clone --depth 1 "https://$GIT_TOKEN@github.com/${currentConfig[repoUrl]}" -b "${currentConfig[branch]}" "$tgtDir"
  
  # Get current database version
  currentDbVersion=$(PGPASSWORD=$PGPASSWORD psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER_NAME" -d orchestrator -t -c "SELECT version FROM schema_migrations;" | xargs)
  echo "Current database version: $currentDbVersion"
  
  # Remove leading zeros for comparison
  sourceLatestClean=$(echo "$sourceLatestMigration" | sed 's/^0*//')
  sourceLatestClean=${sourceLatestClean:-0}
  currentDbVersionClean=$(echo "$currentDbVersion" | sed 's/^0*//')
  currentDbVersionClean=${currentDbVersionClean:-0}
  
  echo "Comparing migrations: source=$sourceLatestClean, current_db=$currentDbVersionClean"
  
  # Get list of target migrations and count steps
  pushd "$tgtDir/${currentConfig[directory]}" > /dev/null
  
  # Get all down migration files
  mapfile -t targetMigrations < <(ls | grep -E '^[0-9]+.*\.down\.sql$' | sort -rn)
  
  echo "Total down migration files found: ${#targetMigrations[@]}"
  
  # Collect migrations to display and count steps
  migrationsToDisplay=()
  stepsToRun=0
  
  for mig in "${targetMigrations[@]}"; do
    migNum=$(echo "$mig" | grep -oE '^[0-9]+')
    migNumClean=$(echo "$migNum" | sed 's/^0*//')
    migNumClean=${migNumClean:-0}
    
    # Migrations to display: all that are > sourceLatest
    if (( migNumClean > sourceLatestClean )); then
      migrationsToDisplay+=("$mig")
    fi
    
    # Steps to run: only those > sourceLatest AND <= currentDb
    if (( migNumClean > sourceLatestClean && migNumClean <= currentDbVersionClean )); then
      ((stepsToRun++))
    fi
  done
  
  echo "${currentConfig[cloneDir]}: Down migrations to run count: ${#migrationsToDisplay[@]}"
  if [ ${#migrationsToDisplay[@]} -gt 0 ]; then
    echo "Migration files to run down: ${migrationsToDisplay[*]}"
  fi
  echo "Actual down steps to execute: $stepsToRun"
  
  # Run down migrations in a single batch
  if [ $stepsToRun -gt 0 ]; then
    echo "Executing $stepsToRun down migration(s) for ${currentConfig[cloneDir]}"
    migrate -path . -database "postgres://$DB_USER_NAME:$PGPASSWORD@$DB_HOST:$DB_PORT/orchestrator?sslmode=disable" -verbose down $stepsToRun
    echo "✓ Completed down migrations for ${currentConfig[cloneDir]}"
  else
    echo "No migrations to execute for ${currentConfig[cloneDir]}"
  fi
  
  popd > /dev/null
done

echo "===================================================="
echo "✓ Migration check completed successfully"
echo "===================================================="
