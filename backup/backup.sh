#!/bin/bash

# PostgreSQL Backup Script
# This script creates a timestamped backup of the PostgreSQL database
# and syncs it to both local and remote storage

set -e

# Configuration
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
BACKUP_DIR="/backups"
REMOTE_DIR="/remote"
BACKUP_FILE="backup_${TIMESTAMP}.sql.gz"
LOG_FILE="/var/log/cron.log"

# Log function
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a $LOG_FILE
}

# Check if required environment variables are set
if [ -z "$PGHOST" ] || [ -z "$PGUSER" ] || [ -z "$PGPASSWORD" ] || [ -z "$PGDATABASE" ]; then
    log "ERROR: Required environment variables are not set"
    log "PGHOST: $PGHOST, PGUSER: $PGUSER, PGDATABASE: $PGDATABASE"
    exit 1
fi

# Create backup directory if it doesn't exist
mkdir -p $BACKUP_DIR
mkdir -p $REMOTE_DIR

log "Starting backup process for database: $PGDATABASE"

# Test database connection
if ! pg_isready -h $PGHOST -U $PGUSER -d $PGDATABASE > /dev/null 2>&1; then
    log "ERROR: Cannot connect to PostgreSQL database"
    exit 1
fi

log "Database connection successful"

# Create backup
log "Creating backup: $BACKUP_FILE"
if pg_dump -h $PGHOST -U $PGUSER -d $PGDATABASE | gzip > "$BACKUP_DIR/$BACKUP_FILE"; then
    log "Backup created successfully: $BACKUP_FILE"
    
    # Get backup size
    BACKUP_SIZE=$(du -h "$BACKUP_DIR/$BACKUP_FILE" | cut -f1)
    log "Backup size: $BACKUP_SIZE"
    
    # Sync to remote storage
    log "Syncing backup to remote storage..."
    if rsync -av --delete "$BACKUP_DIR/$BACKUP_FILE" "$REMOTE_DIR/"; then
        log "Backup synced to remote storage successfully"
    else
        log "WARNING: Failed to sync backup to remote storage"
    fi
    
    # Clean up old backups (keep last 7 days)
    log "Cleaning up old backups (keeping last 7 days)..."
    find $BACKUP_DIR -name "backup_*.sql.gz" -mtime +7 -delete
    find $REMOTE_DIR -name "backup_*.sql.gz" -mtime +7 -delete
    
    # List current backups
    log "Current backups in local storage:"
    ls -lh $BACKUP_DIR/backup_*.sql.gz 2>/dev/null || log "No local backups found"
    
    log "Current backups in remote storage:"
    ls -lh $REMOTE_DIR/backup_*.sql.gz 2>/dev/null || log "No remote backups found"
    
    log "Backup process completed successfully"
else
    log "ERROR: Failed to create backup"
    exit 1
fi
