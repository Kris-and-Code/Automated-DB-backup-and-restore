#!/bin/bash

# InfluxDB Restore Script
# Restores database from backup files

set -e

# Default values
BACKUP_FILE="${1:-}"
BACKUP_DIR="/backups"
REMOTE_DIR="/remote"
LOG_FILE="/var/log/restore.log"
TEMP_DIR="/tmp/restore_$(date +%Y%m%d_%H%M%S)"

# Log function
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

# Error handling
error_exit() {
    log "ERROR: $1"
    # Cleanup temp directory
    [ -d "$TEMP_DIR" ] && rm -rf "$TEMP_DIR"
    exit 1
}

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if InfluxDB CLI is available
    if ! command -v influx >/dev/null 2>&1; then
        error_exit "InfluxDB CLI not found"
    fi
    
    # Check if backup directory exists
    if [ ! -d "$BACKUP_DIR" ]; then
        error_exit "Backup directory $BACKUP_DIR does not exist"
    fi
    
    # Check if remote directory exists
    if [ ! -d "$REMOTE_DIR" ]; then
        error_exit "Remote directory $REMOTE_DIR does not exist"
    fi
    
    log "Prerequisites check passed"
}

# List available backups
list_backups() {
    log "Available backups:"
    echo ""
    echo "Local backups:"
    if [ -d "$BACKUP_DIR" ]; then
        find "$BACKUP_DIR" -name "influxdb_*.tar.gz*" -type f 2>/dev/null | sort | while read -r file; do
            local size=$(du -h "$file" | cut -f1)
            local date=$(stat -c%y "$file" | cut -d' ' -f1)
            echo "  $(basename "$file") - $size - $date"
        done
    else
        echo "  No local backups found"
    fi
    
    echo ""
    echo "Remote backups:"
    if [ -d "$REMOTE_DIR" ]; then
        find "$REMOTE_DIR" -name "influxdb_*.tar.gz*" -type f 2>/dev/null | sort | while read -r file; do
            local size=$(du -h "$file" | cut -f1)
            local date=$(stat -c%y "$file" | cut -d' ' -f1)
            echo "  $(basename "$file") - $size - $date"
        done
    else
        echo "  No remote backups found"
    fi
}

# Find backup file
find_backup() {
    local backup_name="$1"
    
    # Check local directory first
    if [ -f "$BACKUP_DIR/$backup_name" ]; then
        echo "$BACKUP_DIR/$backup_name"
        return 0
    fi
    
    # Check remote directory
    if [ -f "$REMOTE_DIR/$backup_name" ]; then
        echo "$REMOTE_DIR/$backup_name"
        return 0
    fi
    
    # Try to find by pattern
    local local_file=$(find "$BACKUP_DIR" -name "*$backup_name*" -type f 2>/dev/null | head -n1)
    if [ -n "$local_file" ]; then
        echo "$local_file"
        return 0
    fi
    
    local remote_file=$(find "$REMOTE_DIR" -name "*$backup_name*" -type f 2>/dev/null | head -n1)
    if [ -n "$remote_file" ]; then
        echo "$remote_file"
        return 0
    fi
    
    return 1
}

# Test InfluxDB connection
test_connection() {
    log "Testing InfluxDB connection..."
    
    if ! influx ping --host "$INFLUXDB_URL" --token "$INFLUXDB_TOKEN"; then
        error_exit "Cannot connect to InfluxDB at $INFLUXDB_URL"
    fi
    
    log "InfluxDB connection successful"
}

# Prepare backup file
prepare_backup() {
    local backup_file="$1"
    
    log "Preparing backup file: $backup_file"
    
    # Create temporary directory
    mkdir -p "$TEMP_DIR"
    
    # Check if file is encrypted
    if [[ "$backup_file" == *.enc ]]; then
        log "Backup file is encrypted, decrypting..."
        if ! decrypt_file "$backup_file"; then
            error_exit "Failed to decrypt backup file"
        fi
        backup_file="${backup_file%.enc}"
    fi
    
    # Extract backup archive
    log "Extracting backup archive..."
    if ! tar -xzf "$backup_file" -C "$TEMP_DIR"; then
        error_exit "Failed to extract backup archive"
    fi
    
    # Check for metadata
    if [ -f "$TEMP_DIR/metadata.json" ]; then
        log "Backup metadata:"
        cat "$TEMP_DIR/metadata.json" | jq '.' 2>/dev/null || cat "$TEMP_DIR/metadata.json"
    fi
    
    log "Backup preparation completed"
}

# Restore database
restore_database() {
    log "Starting database restore..."
    
    # Check if data directory exists
    if [ ! -d "$TEMP_DIR/data" ]; then
        error_exit "Backup data directory not found"
    fi
    
    # Import data to InfluxDB
    log "Importing data to InfluxDB..."
    if ! influx import \
        --host "$INFLUXDB_URL" \
        --token "$INFLUXDB_TOKEN" \
        --org "$INFLUXDB_ORG" \
        --bucket "$INFLUXDB_BUCKET" \
        --path "$TEMP_DIR/data"; then
        error_exit "Failed to import data to InfluxDB"
    fi
    
    log "Database restore completed successfully"
}

# Verify restore
verify_restore() {
    log "Verifying restore..."
    
    # Check if data was imported
    local measurement_count=$(influx query \
        --host "$INFLUXDB_URL" \
        --token "$INFLUXDB_TOKEN" \
        --org "$INFLUXDB_ORG" \
        "from(bucket:\"$INFLUXDB_BUCKET\") |> range(start: -1h) |> count()" 2>/dev/null | grep -o '[0-9]*' | tail -n1 || echo "0")
    
    if [ "$measurement_count" -gt 0 ]; then
        log "Restore verification passed: $measurement_count measurements found"
        return 0
    else
        log "WARNING: No measurements found after restore"
        return 1
    fi
}

# Cleanup
cleanup() {
    log "Cleaning up temporary files..."
    if [ -d "$TEMP_DIR" ]; then
        rm -rf "$TEMP_DIR"
    fi
    log "Cleanup completed"
}

# Main execution
main() {
    log "Starting InfluxDB restore process"
    
    # Check prerequisites
    check_prerequisites
    
    # If no backup file specified, list available backups
    if [ -z "$BACKUP_FILE" ]; then
        list_backups
        echo ""
        echo "Usage: $0 <backup-file-name>"
        echo "Example: $0 influxdb_full_20241201_120000.tar.gz"
        exit 0
    fi
    
    # Find backup file
    local actual_backup_file
    if actual_backup_file=$(find_backup "$BACKUP_FILE"); then
        log "Found backup file: $actual_backup_file"
    else
        error_exit "Backup file not found: $BACKUP_FILE"
    fi
    
    # Test connection
    test_connection
    
    # Prepare backup
    prepare_backup "$actual_backup_file"
    
    # Restore database
    restore_database
    
    # Verify restore
    verify_restore
    
    # Cleanup
    cleanup
    
    log "Restore process completed successfully"
}

# Trap cleanup on exit
trap cleanup EXIT

# Run main function
main "$@"
