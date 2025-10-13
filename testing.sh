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
  sourceLatestMigration=$((10#$sourceLatestMigration))  # Strip leading zeros
  popd > /dev/null
  echo "Source-of-truth latest migration: $sourceLatestMigration"

  # Clone target branch
  tgtDir="testing-${currentConfig[cloneDir]}-${currentConfig[branch]}"
  echo "Cloning target branch ${currentConfig[branch]} into $tgtDir"
  git clone --depth 1 "https://$GIT_TOKEN@github.com/${currentConfig[repoUrl]}" -b "${currentConfig[branch]}" "$tgtDir"

  # Get list of down migrations
  pushd "$tgtDir/${currentConfig[directory]}" > /dev/null
  targetMigrations=( $(ls | grep -E '^[0-9]+.*\.down\.sql$' | sort -rn) )

  # Collect down migrations (those greater than sourceLatestMigration)
  migrationsToRunDown=()
  for mig in "${targetMigrations[@]}"; do
    migNum=$(echo "$mig" | grep -oE '^[0-9]+')
    migNum=$((10#$migNum))
    if (( migNum > sourceLatestMigration )); then
      migrationsToRunDown+=("$mig")
    fi
  done

  echo "${currentConfig[cloneDir]}: Down migrations to run count: ${#migrationsToRunDown[@]}"
  echo "Migration files to run down: ${migrationsToRunDown[*]}"

  # Run down migrations one by one
  for ((i=0; i<${#migrationsToRunDown[@]}; i++)); do
    migFile="${migrationsToRunDown[$i]}"
    echo "Running down migration $((i+1)) for ${currentConfig[cloneDir]}: $migFile"

    migNum=$(echo "$migFile" | grep -oE '^[0-9]+')
    migNum=$((10#$migNum))

    # Run migrate: force to version, then down 1
    migrate -path "$PWD" \
        -database "postgres://$DB_USER_NAME:$PGPASSWORD@$DB_HOST:$DB_PORT/orchestrator?sslmode=disable" \
        force "$migNum"

    migrate -path "$PWD" \
        -database "postgres://$DB_USER_NAME:$DB_PASSWORD@$DB_HOST:$DB_PORT/orchestrator?sslmode=disable" \
        down 1 -verbose

    # Show current schema_migrations
    psql "postgres://$DB_USER_NAME:$DB_PASSWORD@$DB_HOST:$DB_PORT/orchestrator?sslmode=disable" \
        -c "SELECT version, dirty FROM schema_migrations;"
  done

  popd > /dev/null
done
