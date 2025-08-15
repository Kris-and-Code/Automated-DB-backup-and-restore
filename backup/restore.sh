#!/bin/bash

# PostgreSQL Restore Script
# This script restores a PostgreSQL database from a specified backup file

set -e

# Configuration
BACKUP_DIR="/backups"
REMOTE_DIR="/remote"
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

# Function to show usage
show_usage() {
    echo "Usage: $0 [OPTIONS] <backup_file>"
    echo ""
    echo "Options:"
    echo "  -h, --help          Show this help message"
    echo "  -l, --list          List available backup files"
    echo "  -f, --force         Force restore without confirmation"
    echo "  -r, --remote        Use remote backup directory instead of local"
    echo ""
    echo "Examples:"
    echo "  $0 backup_20241201_020000.sql.gz"
    echo "  $0 -r backup_20241201_020000.sql.gz"
    echo "  $0 -l"
    echo ""
    echo "Note: This will DESTROY the current database and replace it with the backup!"
}

# Function to list available backups
list_backups() {
    local dir_type="$1"
    local dir_path="$2"
    
    echo "Available backups in $dir_type directory ($dir_path):"
    if [ -d "$dir_path" ]; then
        local backups=$(find "$dir_path" -name "backup_*.sql.gz" -type f 2>/dev/null | sort -r)
        if [ -n "$backups" ]; then
            echo "$backups" | while read -r backup; do
                local size=$(du -h "$backup" | cut -f1)
                local date=$(basename "$backup" | sed 's/backup_\([0-9]\{8\}\)_\([0-9]\{6\}\)\.sql\.gz/\1 \2/' | sed 's/\([0-9]\{4\}\)\([0-9]\{2\}\)\([0-9]\{2\}\)/\1-\2-\3/' | sed 's/\([0-9]\{2\}\)\([0-9]\{2\}\)\([0-9]\{2\}\)/\1:\2:\3/')
                echo "  $(basename "$backup") - Size: $size, Date: $date"
            done
        else
            echo "  No backup files found"
        fi
    else
        echo "  Directory does not exist"
    fi
    echo ""
}

# Parse command line arguments
FORCE_RESTORE=false
USE_REMOTE=false
BACKUP_FILE=""

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_usage
            exit 0
            ;;
        -l|--list)
            echo "=== Available Backups ==="
            list_backups "local" "$BACKUP_DIR"
            list_backups "remote" "$REMOTE_DIR"
            exit 0
            ;;
        -f|--force)
            FORCE_RESTORE=true
            shift
            ;;
        -r|--remote)
            USE_REMOTE=true
            shift
            ;;
        -*)
            echo "Unknown option: $1"
            show_usage
            exit 1
            ;;
        *)
            BACKUP_FILE="$1"
            shift
            ;;
    esac
done

# Check if backup file is specified
if [ -z "$BACKUP_FILE" ]; then
    echo "ERROR: No backup file specified"
    show_usage
    exit 1
fi

# Determine backup directory
if [ "$USE_REMOTE" = true ]; then
    BACKUP_PATH="$REMOTE_DIR/$BACKUP_FILE"
    BACKUP_SOURCE="remote"
else
    BACKUP_PATH="$BACKUP_DIR/$BACKUP_FILE"
    BACKUP_SOURCE="local"
fi

# Check if backup file exists
if [ ! -f "$BACKUP_PATH" ]; then
    log "ERROR: Backup file not found: $BACKUP_PATH"
    echo "Available backups in $BACKUP_SOURCE directory:"
    if [ "$USE_REMOTE" = true ]; then
        list_backups "remote" "$REMOTE_DIR"
    else
        list_backups "local" "$BACKUP_DIR"
    fi
    exit 1
fi

# Test database connection
log "Testing database connection..."
if ! pg_isready -h $PGHOST -U $PGUSER -d $PGDATABASE > /dev/null 2>&1; then
    log "ERROR: Cannot connect to PostgreSQL database"
    exit 1
fi

log "Database connection successful"

# Show backup file information
BACKUP_SIZE=$(du -h "$BACKUP_PATH" | cut -f1)
log "Backup file: $BACKUP_FILE"
log "Source: $BACKUP_SOURCE directory"
log "Size: $BACKUP_SIZE"

# Confirm restore (unless forced)
if [ "$FORCE_RESTORE" = false ]; then
    echo ""
    echo "WARNING: This will DESTROY the current database '$PGDATABASE' and replace it with the backup!"
    echo "Backup file: $BACKUP_FILE"
    echo "Size: $BACKUP_SIZE"
    echo ""
    read -p "Are you sure you want to continue? (yes/no): " confirm
    
    if [ "$confirm" != "yes" ]; then
        log "Restore cancelled by user"
        exit 0
    fi
fi

# Perform restore
log "Starting database restore from: $BACKUP_FILE"

# Drop and recreate database
log "Dropping existing database..."
dropdb -h $PGHOST -U $PGUSER --if-exists $PGDATABASE

log "Creating new database..."
createdb -h $PGHOST -U $PGUSER $PGDATABASE

# Restore from backup
log "Restoring database from backup..."
if gunzip -c "$BACKUP_PATH" | psql -h $PGHOST -U $PGUSER -d $PGDATABASE; then
    log "Database restore completed successfully!"
    
    # Verify restore by checking table count
    TABLE_COUNT=$(psql -h $PGHOST -U $PGUSER -d $PGDATABASE -t -c "SELECT count(*) FROM information_schema.tables WHERE table_schema = 'public';" | tr -d ' ')
    log "Restored database contains $TABLE_COUNT tables"
    
    # Show sample data
    log "Sample data from restored database:"
    psql -h $PGHOST -U $PGUSER -d $PGDATABASE -c "SELECT 'Users table:' as info; SELECT username, email FROM users LIMIT 3;"
    psql -h $PGHOST -U $PGUSER -d $PGDATABASE -c "SELECT 'Products table:' as info; SELECT name, price, stock_quantity FROM products LIMIT 3;"
    
else
    log "ERROR: Database restore failed"
    exit 1
fi
