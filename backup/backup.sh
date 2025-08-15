#!/bin/bash

# InfluxDB Backup Script
# Performs incremental and full backups with compression and encryption

set -e

# Source configuration
source /usr/local/bin/backup_utils.sh

# Default values
BACKUP_TYPE="${1:-incremental}"
BACKUP_DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR="/backups"
REMOTE_DIR="/remote"
LOG_FILE="/var/log/backup.log"

# Log function
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

# Error handling
error_exit() {
    log "ERROR: $1"
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

# Test InfluxDB connection
test_connection() {
    log "Testing InfluxDB connection..."
    
    if ! influx ping --host "$INFLUXDB_URL" --token "$INFLUXDB_TOKEN"; then
        error_exit "Cannot connect to InfluxDB at $INFLUXDB_URL"
    fi
    
    log "InfluxDB connection successful"
}

# Create backup
create_backup() {
    local backup_name="influxdb_${BACKUP_TYPE}_${BACKUP_DATE}"
    local backup_file="${BACKUP_DIR}/${backup_name}.tar.gz"
    local temp_dir="/tmp/${backup_name}"
    
    log "Creating $BACKUP_TYPE backup: $backup_name"
    
    # Create temporary directory
    mkdir -p "$temp_dir"
    
    # Export InfluxDB data
    log "Exporting InfluxDB data..."
    if ! influx export \
        --host "$INFLUXDB_URL" \
        --token "$INFLUXDB_TOKEN" \
        --org "$INFLUXDB_ORG" \
        --bucket "$INFLUXDB_BUCKET" \
        --output "$temp_dir/data" \
        --start "$(get_backup_start_time)" \
        --end "$(date -u +%Y-%m-%dT%H:%M:%SZ)"; then
        error_exit "Failed to export InfluxDB data"
    fi
    
    # Create metadata file
    cat > "$temp_dir/metadata.json" << EOF
{
    "backup_type": "$BACKUP_TYPE",
    "backup_date": "$BACKUP_DATE",
    "influxdb_version": "$(influx version | head -n1)",
    "bucket": "$INFLUXDB_BUCKET",
    "org": "$INFLUXDB_ORG",
    "start_time": "$(get_backup_start_time)",
    "end_time": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "compression": "gzip",
    "encryption": "AES-256"
}
EOF
    
    # Compress and encrypt backup
    log "Compressing and encrypting backup..."
    if ! tar -czf "$backup_file" -C "$temp_dir" .; then
        error_exit "Failed to compress backup"
    fi
    
    # Encrypt backup (if encryption key is set)
    if [ -n "$ENCRYPTION_KEY" ]; then
        log "Encrypting backup..."
        if ! encrypt_file "$backup_file"; then
            error_exit "Failed to encrypt backup"
        fi
    fi
    
    # Clean up temporary directory
    rm -rf "$temp_dir"
    
    # Verify backup integrity
    log "Verifying backup integrity..."
    if ! verify_backup "$backup_file"; then
        error_exit "Backup verification failed"
    fi
    
    log "Backup created successfully: $backup_file"
    echo "$backup_file"
}

# Get backup start time based on type
get_backup_start_time() {
    case "$BACKUP_TYPE" in
        "incremental")
            # Start from last backup (24 hours ago for demo)
            date -u -d "24 hours ago" +%Y-%m-%dT%H:%M:%SZ
            ;;
        "full")
            # Start from beginning of time
            echo "1970-01-01T00:00:00Z"
            ;;
        *)
            error_exit "Invalid backup type: $BACKUP_TYPE"
            ;;
    esac
}

# Main execution
main() {
    log "Starting InfluxDB backup process"
    
    # Check prerequisites
    check_prerequisites
    
    # Test connection
    test_connection
    
    # Create backup
    backup_file=$(create_backup)
    
    # Copy to remote storage
    log "Copying backup to remote storage..."
    if ! copy_to_remote "$backup_file" "$REMOTE_DIR"; then
        log "WARNING: Failed to copy backup to remote storage"
    fi
    
    # Cleanup old backups
    log "Cleaning up old backups..."
    cleanup_old_backups
    
    log "Backup process completed successfully"
}

# Run main function
main "$@"
