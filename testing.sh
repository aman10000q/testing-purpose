#!/bin/bash
set -euo pipefail

echo " Testing the Database Connection..."
PGPASSWORD=$PGPASSWORD psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER_NAME" -d orchestrator -t -c "SELECT * FROM schema_migrations;" >/dev/null
echo " Database connection successful."

# -------------------------------
# MIGRATION CONFIGS
# -------------------------------

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

# Array of associative array names
migrationConfigs=(orchMigrationConfig casbinMigrationConfig gitSensorMigrationConfig lensMigrationConfig)

# -------------------------------
# MIGRATION LOOP
# -------------------------------

for configName in "${migrationConfigs[@]}"; do
  declare -n currentConfig="$configName"

  sourceOfTruthLatestMigration=0
  targetLatestMigration=0

  echo "===================================================="
  echo "🔧 Checking migrations for ${currentConfig[cloneDir]}"
  echo "Repo: ${currentConfig[repoUrl]}"
  echo "Branch: ${currentConfig[branch]}"
  echo "===================================================="

  # Compare sourceOfTruth branch with target branch
  for branch in "$sourceOfTruth" "${currentConfig[branch]}"; do
    directoryForCloning="repo-${currentConfig[cloneDir]}-$branch"
    repoUrl="https://$GIT_TOKEN@github.com/${currentConfig[repoUrl]}"

    echo " Cloning $repoUrl (branch: $branch)..."
    git clone --depth 1 -b "$branch" "$repoUrl" "$directoryForCloning" >/dev/null 2>&1

    pushd "$directoryForCloning/${currentConfig[directory]}" >/dev/null

    # Get highest migration number (based on file prefix)
    latestMigration=$(ls | grep -E '^[0-9]+' | sed -E 's/^([0-9]+).*/\1/' | sort -n | tail -1 || echo 0)

    if [[ "$branch" == "$sourceOfTruth" ]]; then
      sourceOfTruthLatestMigration=$latestMigration
      echo " Source-of-truth migration: $sourceOfTruthLatestMigration"
    else
      targetLatestMigration=$latestMigration
      echo "Target branch migration: $targetLatestMigration"

      diff=$((targetLatestMigration - sourceOfTruthLatestMigration))
      if (( diff < 0 )); then
        diff=$((diff * -1))
      fi
      currentConfig[migToRunDown]=$diff
    fi

    popd >/dev/null
  done

  echo " ${currentConfig[cloneDir]}: Migrations to run down: ${currentConfig[migToRunDown]}"

  # Run down migrations if required
  if (( currentConfig[migToRunDown] > 0 )); then
    echo "Running ${currentConfig[migToRunDown]} down migrations for ${currentConfig[cloneDir]}..."

    migrate -path "$directoryForCloning/${currentConfig[directory]}" \
      -database "postgres://$DB_USER_NAME:$PGPASSWORD@$DB_HOST:$DB_PORT/orchestrator?sslmode=disable" \
      down "${currentConfig[migToRunDown]}" || {
        echo " Migration failed for ${currentConfig[cloneDir]}"
        exit 1
      }

    echo " Successfully ran ${currentConfig[migToRunDown]} down migrations for ${currentConfig[cloneDir]}"

  else
    echo " No down migrations needed for ${currentConfig[cloneDir]}"
  fi

  # Verify schema_migrations table
  echo " Verifying schema_migrations table for ${currentConfig[cloneDir]}:"
  PGPASSWORD=$PGPASSWORD psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER_NAME" -d orchestrator -c "SELECT version, dirty FROM schema_migrations;"

  # Cleanup cloned repo
  rm -rf "$directoryForCloning"

done

echo " All migrations processed successfully!"
