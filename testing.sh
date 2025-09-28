#!/bin/bash
echo "Testing the Database Connection:"
PGPASSWORD=$PGPASSWORD psql -h $DB_HOST -p $DB_PORT -U $DB_USER_NAME -d orchestrator -t -c "select * from schema_migrations;"
