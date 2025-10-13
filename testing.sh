#!/bin/bash
set -e

echo "Testing the Database Connection..."
PGPASSWORD=$PGPASSWORD psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER_NAME" -d orchestrator -t -c "SELECT 1;" >/dev/null
echo "Database connection successful."
echo

# ----------------------------
# MIGRATION CONFIGURATIONS
# ----------------------------
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

#migrationConfigs=(orchMigrationConfig casbinMigrationConfig gitSensorMigrationConfig lensMigrationConfig)
migrationConfigs=(orchMigrationConfig)


# ----------------------------
# MAIN LOOP
# ----------------------------
for configName in "${migrationConfigs[@]}"; do
  declare -n currentConfig="$configName"

  echo "===================================================="
  echo "🔧 Checking migrations for ${currentConfig[cloneDir]}"
  echo "Repo: ${currentConfig[repoUrl]}"
  echo "Branch: ${currentConfig[branch]}"
  echo "===================================================="

  sourceOfTruthLatestMigration=0
  targetLatestMigration=0

  # Skip if same as source-of-truth
  if [[ "${currentConfig[branch]}" == "$sourceOfTruth" ]]; then
    echo "[INFO] Source-of-truth and target branch are same (${currentConfig[branch]}). Skipping comparison."
    continue
  fi

  for branch in "$sourceOfTruth" "${currentConfig[branch]}"; do
    directoryForCloning="testing-${currentConfig[cloneDir]}-$branch"
    repoUrl="https://$GIT_TOKEN@github.com/${currentConfig[repoUrl]}"

    echo "Cloning $repoUrl (branch: $branch)..."
    rm -rf "$directoryForCloning"
    git clone --depth 1 "$repoUrl" -b "$branch" "$directoryForCloning"

    pushd "$directoryForCloning/${currentConfig[directory]}" >/dev/null

    latestMigration=$(ls | grep -E '^[0-9]+' | sed -E 's/^([0-9]+).*/\1/' | sort -n | tail -1 || echo 0)
    echo "Latest migration in $branch: $latestMigration"

    if [[ "$branch" == "$sourceOfTruth" ]]; then
      sourceOfTruthLatestMigration=$latestMigration
    else
      targetLatestMigration=$latestMigration
      currentConfig[migToRunDown]=$((targetLatestMigration - sourceOfTruthLatestMigration))
    fi

    popd >/dev/null
  done

  echo "${currentConfig[cloneDir]}: Migrations to run down: ${currentConfig[migToRunDown]}"

  # ----------------------------
  # RUN DOWN MIGRATIONS
  # ----------------------------
  if [[ ${currentConfig[migToRunDown]} -gt 0 ]]; then
    migrationDir="testing-${currentConfig[cloneDir]}-${currentConfig[branch]}/${currentConfig[directory]}"
    echo "Running ${currentConfig[migToRunDown]} down migrations in $migrationDir..."

    pushd "$migrationDir" >/dev/null
    migrate -path . -database "postgres://$DB_USER_NAME:$PGPASSWORD@$DB_HOST:$DB_PORT/orchestrator?sslmode=disable" down ${currentConfig[migToRunDown]}
    popd >/dev/null

    echo "Schema migrations table updated automatically by migrate tool."
  else
    echo "No migrations to run down."
  fi

  echo
done
