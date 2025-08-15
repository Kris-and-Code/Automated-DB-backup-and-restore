#!/bin/bash

# InfluxDB Backup Service Entrypoint
# Initializes the backup service and starts cron

set -e

# Log function
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1"
}

# Check if required environment variables are set
check_environment() {
    log "Checking environment variables..."
    
    local required_vars=("INFLUXDB_URL" "INFLUXDB_TOKEN" "INFLUXDB_ORG" "INFLUXDB_BUCKET")
    local missing_vars=()
    
    for var in "${required_vars[@]}"; do
        if [ -z "${!var}" ]; then
            missing_vars+=("$var")
        fi
    done
    
    if [ ${#missing_vars[@]} -gt 0 ]; then
        log "ERROR: Missing required environment variables: ${missing_vars[*]}"
        exit 1
    fi
    
    log "Environment variables check passed"
}

# Initialize backup directories
init_directories() {
    log "Initializing backup directories..."
    
    # Create necessary directories
    mkdir -p /backups /remote /var/log /scripts
    
    # Set proper permissions
    chown -R backup:backup /backups /remote /var/log /scripts
    chmod 755 /backups /remote /var/log /scripts
    
    log "Directory initialization completed"
}

# Setup cron jobs
setup_cron() {
    log "Setting up cron jobs..."
    
    # Copy crontab file
    cp /etc/cron.d/backup /tmp/backup_cron
    
    # Replace placeholders with actual values
    sed -i "s|INFLUXDB_URL|$INFLUXDB_URL|g" /tmp/backup_cron
    sed -i "s|INFLUXDB_TOKEN|$INFLUXDB_TOKEN|g" /tmp/backup_cron
    sed -i "s|INFLUXDB_ORG|$INFLUXDB_ORG|g" /tmp/backup_cron
    sed -i "s|INFLUXDB_BUCKET|$INFLUXDB_BUCKET|g" /tmp/backup_cron
    
    # Install crontab
    crontab /tmp/backup_cron
    
    # Clean up temporary file
    rm /tmp/backup_cron
    
    log "Cron jobs configured"
}

# Test InfluxDB connection
test_connection() {
    log "Testing InfluxDB connection..."
    
    # Wait for InfluxDB to be ready
    local max_attempts=30
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        if influx ping --host "$INFLUXDB_URL" --token "$INFLUXDB_TOKEN" >/dev/null 2>&1; then
            log "InfluxDB connection successful"
            return 0
        fi
        
        log "Attempt $attempt/$max_attempts: InfluxDB not ready, waiting..."
        sleep 10
        attempt=$((attempt + 1))
    done
    
    log "ERROR: Failed to connect to InfluxDB after $max_attempts attempts"
    return 1
}

# Start cron service
start_cron() {
    log "Starting cron service..."
    
    # Start cron in foreground
    exec cron -f
}

# Main execution
main() {
    log "Starting InfluxDB Backup Service"
    
    # Check environment
    check_environment
    
    # Initialize directories
    init_directories
    
    # Setup cron jobs
    setup_cron
    
    # Test connection
    test_connection
    
    # Start cron service
    start_cron
}

# Run main function
main "$@"
