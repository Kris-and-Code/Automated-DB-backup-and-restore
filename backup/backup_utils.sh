#!/bin/bash

# InfluxDB Backup Utilities
# Common functions for backup operations

# Environment variables (can be overridden)
ENCRYPTION_KEY="${ENCRYPTION_KEY:-}"
BACKUP_RETENTION_DAYS="${BACKUP_RETENTION_DAYS:-30}"
FULL_BACKUP_RETENTION_DAYS="${FULL_BACKUP_RETENTION_DAYS:-365}"

# Log function
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1"
}

# Encrypt file using AES-256
encrypt_file() {
    local file="$1"
    local encrypted_file="${file}.enc"
    
    if [ -z "$ENCRYPTION_KEY" ]; then
        log "WARNING: No encryption key set, skipping encryption"
        return 0
    fi
    
    log "Encrypting file: $file"
    
    if openssl enc -aes-256-cbc -salt -in "$file" -out "$encrypted_file" -k "$ENCRYPTION_KEY"; then
        # Remove original file after successful encryption
        rm "$file"
        log "File encrypted successfully: $encrypted_file"
        return 0
    else
        log "ERROR: Failed to encrypt file: $file"
        return 1
    fi
}

# Decrypt file
decrypt_file() {
    local encrypted_file="$1"
    local decrypted_file="${encrypted_file%.enc}"
    
    if [ -z "$ENCRYPTION_KEY" ]; then
        log "WARNING: No encryption key set, assuming file is not encrypted"
        return 0
    fi
    
    log "Decrypting file: $encrypted_file"
    
    if openssl enc -aes-256-cbc -d -in "$encrypted_file" -out "$decrypted_file" -k "$ENCRYPTION_KEY"; then
        log "File decrypted successfully: $decrypted_file"
        return 0
    else
        log "ERROR: Failed to decrypt file: $encrypted_file"
        return 1
    fi
}

# Verify backup integrity
verify_backup() {
    local backup_file="$1"
    
    log "Verifying backup integrity: $backup_file"
    
    # Check if file exists
    if [ ! -f "$backup_file" ]; then
        log "ERROR: Backup file not found: $backup_file"
        return 1
    fi
    
    # Check file size
    local file_size=$(stat -c%s "$backup_file")
    if [ "$file_size" -eq 0 ]; then
        log "ERROR: Backup file is empty: $backup_file"
        return 1
    fi
    
    # Test archive integrity
    if [[ "$backup_file" == *.tar.gz ]]; then
        if ! tar -tzf "$backup_file" >/dev/null 2>&1; then
            log "ERROR: Backup archive is corrupted: $backup_file"
            return 1
        fi
    fi
    
    log "Backup verification passed: $backup_file"
    return 0
}

# Copy backup to remote storage
copy_to_remote() {
    local source_file="$1"
    local remote_dir="$2"
    
    log "Copying backup to remote storage: $source_file -> $remote_dir"
    
    # Create remote directory if it doesn't exist
    mkdir -p "$remote_dir"
    
    # Copy file to remote storage
    if cp "$source_file" "$remote_dir/"; then
        log "Backup copied to remote storage successfully"
        
        # Verify copy
        local remote_file="$remote_dir/$(basename "$source_file")"
        if [ -f "$remote_file" ]; then
            local source_size=$(stat -c%s "$source_file")
            local remote_size=$(stat -c%s "$remote_file")
            
            if [ "$source_size" -eq "$remote_size" ]; then
                log "Remote copy verification passed"
                return 0
            else
                log "ERROR: Remote copy size mismatch"
                return 1
            fi
        else
            log "ERROR: Remote file not found after copy"
            return 1
        fi
    else
        log "ERROR: Failed to copy backup to remote storage"
        return 1
    fi
}

# Clean up old backups
cleanup_old_backups() {
    local backup_dir="/backups"
    local remote_dir="/remote"
    
    log "Cleaning up old backups..."
    
    # Clean local backups
    if [ -d "$backup_dir" ]; then
        # Remove old incremental backups
        find "$backup_dir" -name "influxdb_incremental_*.tar.gz*" -mtime +$BACKUP_RETENTION_DAYS -delete 2>/dev/null || true
        
        # Remove old full backups
        find "$backup_dir" -name "influxdb_full_*.tar.gz*" -mtime +$FULL_BACKUP_RETENTION_DAYS -delete 2>/dev/null || true
        
        log "Local backup cleanup completed"
    fi
    
    # Clean remote backups
    if [ -d "$remote_dir" ]; then
        # Remove old incremental backups
        find "$remote_dir" -name "influxdb_incremental_*.tar.gz*" -mtime +$BACKUP_RETENTION_DAYS -delete 2>/dev/null || true
        
        # Remove old full backups
        find "$remote_dir" -name "influxdb_full_*.tar.gz*" -mtime +$FULL_BACKUP_RETENTION_DAYS -delete 2>/dev/null || true
        
        log "Remote backup cleanup completed"
    fi
    
    # Log current backup status
    log "Current backup status:"
    if [ -d "$backup_dir" ]; then
        log "Local backups:"
        ls -lh "$backup_dir"/influxdb_*.tar.gz* 2>/dev/null || log "  No local backups found"
    fi
    
    if [ -d "$remote_dir" ]; then
        log "Remote backups:"
        ls -lh "$remote_dir"/influxdb_*.tar.gz* 2>/dev/null || log "  No remote backups found"
    fi
}

# Get backup statistics
get_backup_stats() {
    local backup_dir="/backups"
    local remote_dir="/remote"
    
    echo "=== Backup Statistics ==="
    echo "Local backups:"
    if [ -d "$backup_dir" ]; then
        local local_count=$(find "$backup_dir" -name "influxdb_*.tar.gz*" 2>/dev/null | wc -l)
        local local_size=$(du -sh "$backup_dir" 2>/dev/null | cut -f1)
        echo "  Count: $local_count"
        echo "  Size: $local_size"
    else
        echo "  Directory not found"
    fi
    
    echo "Remote backups:"
    if [ -d "$remote_dir" ]; then
        local remote_count=$(find "$remote_dir" -name "influxdb_*.tar.gz*" 2>/dev/null | wc -l)
        local remote_size=$(du -sh "$remote_dir" 2>/dev/null | cut -f1)
        echo "  Count: $remote_count"
        echo "  Size: $remote_size"
    else
        echo "  Directory not found"
    fi
    
    echo "Retention policy:"
    echo "  Incremental backups: $BACKUP_RETENTION_DAYS days"
    echo "  Full backups: $FULL_BACKUP_RETENTION_DAYS days"
}

# Test backup utilities
test_utilities() {
    log "Testing backup utilities..."
    
    # Test encryption/decryption
    local test_file="/tmp/test_backup_utils.txt"
    echo "Test content" > "$test_file"
    
    if encrypt_file "$test_file"; then
        local encrypted_file="${test_file}.enc"
        if [ -f "$encrypted_file" ]; then
            log "Encryption test passed"
            
            # Test decryption
            if decrypt_file "$encrypted_file"; then
                log "Decryption test passed"
                
                # Verify content
                if [ "$(cat "$test_file")" = "Test content" ]; then
                    log "Content verification passed"
                else
                    log "ERROR: Content verification failed"
                    return 1
                fi
            else
                log "ERROR: Decryption test failed"
                return 1
            fi
        else
            log "ERROR: Encrypted file not found"
            return 1
        fi
    else
        log "ERROR: Encryption test failed"
        return 1
    fi
    
    # Cleanup test files
    rm -f "$test_file" "${test_file}.enc"
    
    log "All utility tests passed"
    return 0
}

# Export functions for use in other scripts
export -f log encrypt_file decrypt_file verify_backup copy_to_remote cleanup_old_backups get_backup_stats test_utilities
