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

# only orch for now as you used
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

  # Clone source-of-truth branch (to get sourceLatestMigration)
  srcDir="testing-${currentConfig[cloneDir]}-$sourceOfTruth"
  echo "Cloning source-of-truth branch $sourceOfTruth into $srcDir"
  rm -rf "$srcDir"
  git clone --depth 1 "https://$GIT_TOKEN@github.com/${currentConfig[repoUrl]}" -b "$sourceOfTruth" "$srcDir"

  # Get latest migration number for source
  pushd "$srcDir/${currentConfig[directory]}" > /dev/null
  # pick numeric prefix of filenames, sort numerically, pick max
  sourceLatestMigration=$(ls | grep -E '^[0-9]+' | sed -E 's/^([0-9]+).*/\1/' | sed 's/^0*//' | awk '{ if ($0=="") print 0; else print $0 }' | sort -n | tail -1)
  sourceLatestMigration=${sourceLatestMigration:-0}
  popd > /dev/null
  echo "Source-of-truth latest migration: $sourceLatestMigration"

  # Clone target branch (the branch from which we want to run down its extra migrations)
  tgtDir="testing-${currentConfig[cloneDir]}-${currentConfig[branch]}"
  echo "Cloning target branch ${currentConfig[branch]} into $tgtDir"
  rm -rf "$tgtDir"
  git clone --depth 1 "https://$GIT_TOKEN@github.com/${currentConfig[repoUrl]}" -b "${currentConfig[branch]}" "$tgtDir"

  # Go into target migration directory
  pushd "$tgtDir/${currentConfig[directory]}" > /dev/null

  # Collect all migration numbers present (from both .up.sql and .down.sql) and find highest
  allMigs=( $(ls | grep -E '^[0-9]+' | sed -E 's/^([0-9]+).*/\1/' | sed 's/^0*//' | awk '{ if ($0=="") print 0; else print $0 }' | sort -n -r) )
  if [ ${#allMigs[@]} -eq 0 ]; then
    echo "No migration files found in $PWD; skipping."
    popd > /dev/null
    continue
  fi
  targetHighestMigration=${allMigs[0]}
  targetHighestMigration=${targetHighestMigration:-0}
  echo "Target highest migration present in directory: $targetHighestMigration"

  # Get list of .down.sql files sorted descending (highest first)
  targetDownFiles=( $(ls | grep -E '^[0-9]+.*\.down\.sql$' | sort -rn) )

  # Collect the down migrations that are strictly > sourceLatestMigration
  migrationsToRunDown=()
  for f in "${targetDownFiles[@]}"; do
    n=$(echo "$f" | grep -oE '^[0-9]+' | sed 's/^0*//')
    n=${n:-0}
    # convert to decimal safely
    n_dec=$((10#$n))
    src_dec=$((10#$sourceLatestMigration))
    if (( n_dec > src_dec )); then
      migrationsToRunDown+=("$f")
    fi
  done

  echo "${currentConfig[cloneDir]}: Down migrations to run count: ${#migrationsToRunDown[@]}"
  if [ ${#migrationsToRunDown[@]} -gt 0 ]; then
    echo "Migration files to run down (highest first):"
    for mf in "${migrationsToRunDown[@]}"; do echo "  $mf"; done
  else
    echo "No down migrations needed for ${currentConfig[cloneDir]}"
    popd > /dev/null
    continue
  fi

  # IMPORTANT: ensure the migrate tool sees the files in this directory; force DB version to the highest migration present
  # Use decimal coercion to be safe
  targetHighestDec=$((10#$targetHighestMigration))
  echo "Forcing DB reported version to target highest migration: $targetHighestDec (so 'down 1' will step down from highest)."
  migrate -path "$PWD" -database "postgres://$DB_USER_NAME:$PGPASSWORD@$DB_HOST:$DB_PORT/orchestrator?sslmode=disable" force "$targetHighestDec"

  # Now run down 1, N times where N is number of migrationsToRunDown
  count=${#migrationsToRunDown[@]}
  echo "Applying down 1 exactly $count times."
  for ((i=1;i<=count;i++)); do
    echo "==> Running down step $i/$count ..."
    migrate -path "$PWD" -database "postgres://$DB_USER_NAME:$PGPASSWORD@$DB_HOST:$DB_PORT/orchestrator?sslmode=disable" down 1 -verbose

    # Print current schema_migrations for visibility
    echo "Current schema_migrations after step $i:"
    PGPASSWORD=$PGPASSWORD psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER_NAME" -d orchestrator -c "SELECT version, dirty FROM schema_migrations;"
  done

  echo "Done running downs for ${currentConfig[cloneDir]}."

  popd > /dev/null
done

echo "All configured services processed."
