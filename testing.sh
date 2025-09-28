#!/bin/bash
set -e

echo "Testing the Database Connection:"
PGPASSWORD=$PGPASSWORD psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER_NAME" -d orchestrator -t -c "SELECT * FROM schema_migrations;"

echo "Connection done"

# Clone repo
git ls-remote https://$GIT_TOKEN@github.com/devtron-labs/devtron-enterprise
git clone --depth 1 https://$GIT_TOKEN@github.com/devtron-labs/devtron-enterprise -b develop
cd devtron-enterprise/scripts/sql

# Find highest migration number in repo
latest_migration=$(ls | grep -E '^[0-9]+' | sed -E 's/^([0-9]+).*/\1/' | sort -n | tail -1)

echo "Highest migration in repo: $latest_migration"

