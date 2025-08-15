#!/bin/bash

# Start cron service
service cron start

# Wait for PostgreSQL to be ready
echo "Waiting for PostgreSQL to be ready..."
until pg_isready -h $PGHOST -U $PGUSER -d $PGDATABASE; do
    echo "PostgreSQL is unavailable - sleeping"
    sleep 2
done

echo "PostgreSQL is ready!"

# Run initial backup
echo "Running initial backup..."
/scripts/backup.sh

# Keep container running and monitor cron logs
echo "Backup container is running. Cron jobs are scheduled."
echo "Monitoring cron logs..."

# Tail cron logs and keep container alive
tail -f /var/log/cron.log
