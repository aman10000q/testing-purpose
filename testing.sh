#!/bin/bash
set -e

echo "Testing the Database Connection..."
PGPASSWORD=$PGPASSWORD psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER_NAME" -d orchestrator -c "SELECT * FROM schema_migrations;"
echo "Connection done"

# Define migration configs
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

#migrationConfigs=(orchMigrationConfig casbinMigrationConfig gitSensorMigrationConfig lensMigrationConfig)
migrationConfigs=(orchMigrationConfig)

# Loop through each config
for configName in "${migrationConfigs[@]}"; do
  declare -n currentConfig="$configName"

  echo "===================================================="
  echo "🔧 Checking migrations for ${currentConfig[cloneDir]}"
  echo "Repo: ${currentConfig[repoUrl]}"
  echo "Branch: ${currentConfig[branch]}"
  echo "===================================================="

  # Clone source-of-truth and target branch separately
  for branch in "$sourceOfTruth" "${currentConfig[branch]}"; do
    dirName="testing-${currentConfig[cloneDir]}-$branch"
    repoUrl="https://$GIT_TOKEN@github.com/${currentConfig[repoUrl]}"
    
    echo "Cloning $repoUrl branch $branch into $dirName"
    rm -rf "$dirName"
    git clone --depth 1 "$repoUrl" -b "$branch" "$dirName"

    pushd "$dirName/${currentConfig[directory]}" > /dev/null

    latestMigration=$(ls | grep -E '^[0-9]+' | sed -E 's/^([0-9]+).*/\1/' | sort -n | tail -1)
    echo "Latest migration in $branch: $latestMigration"

    if [[ "$branch" == "$sourceOfTruth" ]]; then
      sourceLatest=$latestMigration
    else
      targetLatest=$latestMigration
    fi

    popd > /dev/null
  done

  # Calculate how many down migrations to apply
  toRunDown=$((targetLatest - sourceLatest))
  echo "${currentConfig[cloneDir]}: Down migrations to run: $toRunDown"

  # Run down migrations using migrate CLI
  pushd "testing-${currentConfig[cloneDir]}-${currentConfig[branch]}/${currentConfig[directory]}" > /dev/null
  for ((i=0; i<toRunDown; i++)); do
    echo "Running down migration $((i+1)) for ${currentConfig[cloneDir]}"
    migrate -path . -database "postgres://$DB_USER_NAME:$PGPASSWORD@$DB_HOST:$DB_PORT/orchestrator?sslmode=disable" down 1
  done
  popd > /dev/null

done
