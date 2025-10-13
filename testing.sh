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
  
  # Get list of target migrations
  pushd "$tgtDir/${currentConfig[directory]}" > /dev/null
  targetMigrations=( $(ls | grep -E '^[0-9]+.*\.down\.sql$' | sort -rn) )
  
  # Collect down migrations (those greater than sourceLatestMigration)
  migrationsToRunDown=()
  for mig in "${targetMigrations[@]}"; do
    migNum=$(echo "$mig" | grep -oE '^[0-9]+')
    # Remove leading zeros to avoid octal interpretation
    migNumClean=$(echo "$migNum" | sed 's/^0*//')
    sourceLatestClean=$(echo "$sourceLatestMigration" | sed 's/^0*//')
    
    # Handle empty strings (in case all digits were zeros)
    migNumClean=${migNumClean:-0}
    sourceLatestClean=${sourceLatestClean:-0}
    
    if (( migNumClean > sourceLatestClean )); then
      migrationsToRunDown+=("$mig")
    fi
  done
  
  echo "${currentConfig[cloneDir]}: Down migrations to run count: ${#migrationsToRunDown[@]}"
  if [ ${#migrationsToRunDown[@]} -gt 0 ]; then
    echo "Migration files to run down: ${migrationsToRunDown[*]}"
  fi
  
  # Calculate how many down steps we need
  # Count migrations in target that are > sourceLatestMigration AND <= currentDbVersion
  stepsToRun=0
  currentDbVersionClean=$(echo "$currentDbVersion" | sed 's/^0*//')
  currentDbVersionClean=${currentDbVersionClean:-0}
  
  for mig in "${targetMigrations[@]}"; do
    migNum=$(echo "$mig" | grep -oE '^[0-9]+')
    migNumClean=$(echo "$migNum" | sed 's/^0*//')
    migNumClean=${migNumClean:-0}
    
    if (( migNumClean > sourceLatestClean && migNumClean <= currentDbVersionClean )); then
      ((stepsToRun++))
    fi
  done
  
  echo "Actual down steps to run: $stepsToRun"
  
  # Run down migrations in a single batch
  if [ $stepsToRun -gt 0 ]; then
    echo "Running $stepsToRun down migration(s) for ${currentConfig[cloneDir]}"
    migrate -path . -database "postgres://$DB_USER_NAME:$PGPASSWORD@$DB_HOST:$DB_PORT/orchestrator?sslmode=disable" -verbose down $stepsToRun
    echo "Completed down migrations for ${currentConfig[cloneDir]}"
  else
    echo "No migrations to run down for ${currentConfig[cloneDir]}"
  fi
  
  popd > /dev/null
done
