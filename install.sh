#!/bin/bash

# Automated Database Backup & Restore Pipeline for InfluxDB 2
# Main Installation Script
# Version: 1.0.0

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_DIR="/var/backups/influxdb"
CONFIG_DIR="/etc/influxdb-backup"
LOG_DIR="/var/log/influxdb-backup"
SERVICE_USER="influxdb-backup"

# Logging function
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING:${NC} $1"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1"
    exit 1
}

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        error "This script must be run as root (use sudo)"
    fi
}

# Detect OS and package manager
detect_os() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        OS=$NAME
        VER=$VERSION_ID
    else
        error "Cannot detect OS version"
    fi
    
    log "Detected OS: $OS $VER"
    
    if command -v apt-get &> /dev/null; then
        PKG_MANAGER="apt"
    elif command -v yum &> /dev/null; then
        PKG_MANAGER="yum"
    elif command -v dnf &> /dev/null; then
        PKG_MANAGER="dnf"
    else
        error "Unsupported package manager"
    fi
    
    log "Package manager: $PKG_MANAGER"
}

# Install system dependencies
install_dependencies() {
    log "Installing system dependencies..."
    
    if [[ $PKG_MANAGER == "apt" ]]; then
        apt-get update
        apt-get install -y curl wget gnupg2 software-properties-common \
            openssl gzip tar cron systemd-sysv
    elif [[ $PKG_MANAGER == "yum" ]] || [[ $PKG_MANAGER == "dnf" ]]; then
        if [[ $PKG_MANAGER == "yum" ]]; then
            yum update -y
            yum install -y curl wget gnupg2 openssl gzip tar cronie systemd
        else
            dnf update -y
            dnf install -y curl wget gnupg2 openssl gzip tar cronie systemd
        fi
    fi
    
    log "System dependencies installed successfully"
}

# Create necessary directories
create_directories() {
    log "Creating necessary directories..."
    
    mkdir -p "$BACKUP_DIR"
    mkdir -p "$CONFIG_DIR"
    mkdir -p "$LOG_DIR"
    mkdir -p "$BACKUP_DIR"/{incremental,full,encrypted}
    
    # Set proper permissions
    chmod 750 "$BACKUP_DIR"
    chmod 750 "$CONFIG_DIR"
    chmod 755 "$LOG_DIR"
    
    log "Directories created successfully"
}

# Create backup user
create_backup_user() {
    log "Creating backup user..."
    
    if ! id "$SERVICE_USER" &>/dev/null; then
        useradd -r -s /bin/bash -d "$CONFIG_DIR" "$SERVICE_USER"
        log "User $SERVICE_USER created"
    else
        log "User $SERVICE_USER already exists"
    fi
    
    # Set ownership
    chown -R "$SERVICE_USER:$SERVICE_USER" "$BACKUP_DIR"
    chown -R "$SERVICE_USER:$SERVICE_USER" "$CONFIG_DIR"
    chown -R "$SERVICE_USER:$SERVICE_USER" "$LOG_DIR"
    
    log "Backup user setup completed"
}

# Install InfluxDB
install_influxdb() {
    log "Installing InfluxDB 2..."
    
    if command -v influx &> /dev/null; then
        log "InfluxDB is already installed"
        return
    fi
    
    if [[ $PKG_MANAGER == "apt" ]]; then
        # Add InfluxDB repository
        wget -qO- https://repos.influxdata.com/influxdata-archive_compat.key | apt-key add -
        echo "deb [signed-by=/usr/share/keyrings/influxdata-archive_compat.gpg] https://repos.influxdata.com/debian stable main" | tee /etc/apt/sources.list.d/influxdata.list
        
        apt-get update
        apt-get install -y influxdb2
    elif [[ $PKG_MANAGER == "yum" ]] || [[ $PKG_MANAGER == "dnf" ]]; then
        cat <<EOF | tee /etc/yum.repos.d/influxdata.repo
[influxdata]
name = InfluxData Repository - Stable
baseurl = https://repos.influxdata.com/stable/\$basearch/main
enabled = 1
gpgcheck = 1
gpgkey = https://repos.influxdata.com/influxdata-archive_compat.key
EOF
        
        if [[ $PKG_MANAGER == "yum" ]]; then
            yum install -y influxdb2
        else
            dnf install -y influxdb2
        fi
    fi
    
    log "InfluxDB 2 installed successfully"
}

# Configure InfluxDB
configure_influxdb() {
    log "Configuring InfluxDB..."
    
    # Create configuration directory if it doesn't exist
    mkdir -p /etc/influxdb
    
    # Copy configuration files
    cp "$SCRIPT_DIR/config/influxdb.conf" /etc/influxdb/ 2>/dev/null || {
        # Create basic configuration if file doesn't exist
        cat > /etc/influxdb/config.yml <<EOF
api:
  bind-address: ":8086"
  auth-enabled: true
  log-enabled: true
  write-tracing: false
  pprof-enabled: false
  https-enabled: true
  https-certificate: "/etc/ssl/certs/influxdb.crt"
  https-private-key: "/etc/ssl/private/influxdb.key"

data:
  dir: "/var/lib/influxdb2"
  wal-dir: "/var/lib/influxdb2/wal"
  series-id-set-cache-size: 100

http:
  bind-address: ":8086"
  auth-enabled: true
  log-enabled: true
  write-tracing: false
  pprof-enabled: false
  https-enabled: true
  https-certificate: "/etc/ssl/certs/influxdb.crt"
  https-private-key: "/etc/ssl/private/influxdb.key"

logging:
  level: "info"
  format: "auto"

meta:
  dir: "/var/lib/influxdb2/meta"
  retention-autocreate: true
  logging-enabled: true

storage:
  engine: "tsm1"
  cache-max-memory-size: 1073741824
  cache-snapshot-memory-size: 26214400
  cache-snapshot-write-cold-duration: "10m"
  compact-full-write-cold-duration: "4h"
  max-concurrent-compactions: 0
  max-index-log-file-size: 1048576
  series-file-max-concurrent-compactions: 0
  tsm-use-madv-willneed: false
  validate-keys: false

subscriber:
  enabled: true
  http-timeout: "30s"

tls:
  min-version: "1.2"
  max-version: "1.3"
EOF
    }
    
    # Set proper permissions
    chown influxdb:influxdb /etc/influxdb/config.yml
    chmod 640 /etc/influxdb/config.yml
    
    # Create data directories
    mkdir -p /var/lib/influxdb2/{data,wal,meta}
    chown -R influxdb:influxdb /var/lib/influxdb2
    
    log "InfluxDB configuration completed"
}

# Setup backup scripts
setup_backup_scripts() {
    log "Setting up backup scripts..."
    
    # Copy scripts to system directory
    cp -r "$SCRIPT_DIR/scripts" /usr/local/bin/influxdb-backup-scripts
    
    # Make scripts executable
    chmod +x /usr/local/bin/influxdb-backup-scripts/*/*.sh
    
    # Create symlinks for easy access
    ln -sf /usr/local/bin/influxdb-backup-scripts/backup/backup_incremental.sh /usr/local/bin/influxdb-backup-incremental
    ln -sf /usr/local/bin/influxdb-backup-scripts/backup/backup_full.sh /usr/local/bin/influxdb-backup-full
    ln -sf /usr/local/bin/influxdb-backup-scripts/restore/restore_database.sh /usr/local/bin/influxdb-restore
    ln -sf /usr/local/bin/influxdb-backup-scripts/restore/list_backups.sh /usr/local/bin/influxdb-list-backups
    
    # Set ownership
    chown -R "$SERVICE_USER:$SERVICE_USER" /usr/local/bin/influxdb-backup-scripts
    
    log "Backup scripts setup completed"
}

# Setup systemd services
setup_systemd_services() {
    log "Setting up systemd services..."
    
    # Copy service files
    cp "$SCRIPT_DIR/systemd"/*.service /etc/systemd/system/ 2>/dev/null || {
        # Create basic services if files don't exist
        create_backup_service
        create_monitor_service
        create_restore_service
    }
    
    # Reload systemd
    systemctl daemon-reload
    
    # Enable services
    systemctl enable influxdb-backup.service
    systemctl enable influxdb-monitor.service
    
    log "Systemd services setup completed"
}

# Create backup service
create_backup_service() {
    cat > /etc/systemd/system/influxdb-backup.service <<EOF
[Unit]
Description=InfluxDB Automated Backup Service
After=network.target influxdb.service
Wants=influxdb.service

[Service]
Type=oneshot
User=$SERVICE_USER
Group=$SERVICE_USER
ExecStart=/usr/local/bin/influxdb-backup-scripts/backup/backup_incremental.sh
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF
}

# Create monitor service
create_monitor_service() {
    cat > /etc/systemd/system/influxdb-monitor.service <<EOF
[Unit]
Description=InfluxDB Health Monitoring Service
After=network.target influxdb.service
Wants=influxdb.service

[Service]
Type=simple
User=$SERVICE_USER
Group=$SERVICE_USER
ExecStart=/usr/local/bin/influxdb-backup-scripts/maintenance/verify_backup.sh
ExecReload=/bin/kill -HUP \$MAINPID
Restart=always
RestartSec=300

[Install]
WantedBy=multi-user.target
EOF
}

# Create restore service
create_restore_service() {
    cat > /etc/systemd/system/influxdb-restore.service <<EOF
[Unit]
Description=InfluxDB Restore Service
After=network.target
Conflicts=influxdb.service

[Service]
Type=oneshot
User=$SERVICE_USER
Group=$SERVICE_USER
ExecStart=/usr/local/bin/influxdb-backup-scripts/restore/restore_database.sh
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF
}

# Setup cron jobs
setup_cron_jobs() {
    log "Setting up cron jobs..."
    
    # Create cron file for backup user
    cat > /tmp/influxdb-backup-cron <<EOF
# InfluxDB Backup Cron Jobs
# Daily incremental backup at 2:00 AM
0 2 * * * /usr/local/bin/influxdb-backup-scripts/backup/backup_incremental.sh >> $LOG_DIR/cron.log 2>&1

# Weekly full backup on Sunday at 3:00 AM
0 3 * * 0 /usr/local/bin/influxdb-backup-scripts/backup/backup_full.sh >> $LOG_DIR/cron.log 2>&1

# Daily backup cleanup at 4:00 AM
0 4 * * * /usr/local/bin/influxdb-backup-scripts/maintenance/cleanup_old_backups.sh >> $LOG_DIR/cron.log 2>&1

# Daily backup verification at 5:00 AM
0 5 * * * /usr/local/bin/influxdb-backup-scripts/maintenance/verify_backup.sh >> $LOG_DIR/cron.log 2>&1
EOF
    
    # Install cron jobs for backup user
    crontab -u "$SERVICE_USER" /tmp/influxdb-backup-cron
    
    # Clean up temporary file
    rm /tmp/influxdb-backup-cron
    
    log "Cron jobs setup completed"
}

# Setup configuration files
setup_config_files() {
    log "Setting up configuration files..."
    
    # Copy configuration files
    cp "$SCRIPT_DIR/config"/*.conf "$CONFIG_DIR"/ 2>/dev/null || {
        # Create basic configuration if files don't exist
        create_backup_config
        create_security_config
    }
    
    # Set proper permissions
    chown -R "$SERVICE_USER:$SERVICE_USER" "$CONFIG_DIR"
    chmod 640 "$CONFIG_DIR"/*.conf
    
    log "Configuration files setup completed"
}

# Create backup configuration
create_backup_config() {
    cat > "$CONFIG_DIR/backup.conf" <<EOF
# InfluxDB Backup Configuration

# Backup directories
BACKUP_BASE_DIR="$BACKUP_DIR"
BACKUP_INCREMENTAL_DIR="$BACKUP_DIR/incremental"
BACKUP_FULL_DIR="$BACKUP_DIR/full"
BACKUP_ENCRYPTED_DIR="$BACKUP_DIR/encrypted"

# Retention settings
INCREMENTAL_RETENTION_DAYS=30
FULL_RETENTION_DAYS=84
ENCRYPTED_RETENTION_DAYS=730

# Compression settings
COMPRESSION_LEVEL=6
COMPRESSION_EXTENSION=".gz"

# Encryption settings
ENCRYPTION_ENABLED=true
ENCRYPTION_ALGORITHM="aes-256-gcm"
ENCRYPTION_KEY_FILE="$CONFIG_DIR/encryption.key"

# Logging
LOG_LEVEL="INFO"
LOG_FILE="$LOG_DIR/backup.log"
MAX_LOG_SIZE_MB=100
LOG_RETENTION_DAYS=30

# Notification settings
NOTIFICATION_ENABLED=false
NOTIFICATION_EMAIL=""
SMTP_SERVER=""
SMTP_PORT="587"
SMTP_USERNAME=""
SMTP_PASSWORD=""
EOF
}

# Create security configuration
create_security_config() {
    cat > "$CONFIG_DIR/security.conf" <<EOF
# InfluxDB Security Configuration

# TLS/SSL settings
TLS_ENABLED=true
TLS_CERT_FILE="/etc/ssl/certs/influxdb.crt"
TLS_KEY_FILE="/etc/ssl/private/influxdb.key"
TLS_MIN_VERSION="1.2"
TLS_MAX_VERSION="1.3"

# Authentication settings
AUTH_ENABLED=true
AUTH_TYPE="token"
TOKEN_EXPIRY_DAYS=365

# Network security
BIND_ADDRESS="127.0.0.1:8086"
ALLOWED_ORIGINS="*"
CORS_ENABLED=false

# Backup security
BACKUP_ENCRYPTION=true
BACKUP_ACCESS_CONTROL=true
BACKUP_USER_PERMISSIONS="read-only"
EOF
}

# Generate encryption key
generate_encryption_key() {
    log "Generating encryption key..."
    
    if [[ ! -f "$CONFIG_DIR/encryption.key" ]]; then
        openssl rand -hex 32 > "$CONFIG_DIR/encryption.key"
        chown "$SERVICE_USER:$SERVICE_USER" "$CONFIG_DIR/encryption.key"
        chmod 600 "$CONFIG_DIR/encryption.key"
        log "Encryption key generated successfully"
    else
        log "Encryption key already exists"
    fi
}

# Start and enable InfluxDB
start_influxdb() {
    log "Starting InfluxDB service..."
    
    # Start InfluxDB
    systemctl start influxdb
    
    # Wait for service to be ready
    log "Waiting for InfluxDB to be ready..."
    for i in {1..30}; do
        if curl -s http://localhost:8086/health > /dev/null 2>&1; then
            log "InfluxDB is ready"
            break
        fi
        sleep 2
    done
    
    # Check if service is running
    if systemctl is-active --quiet influxdb; then
        log "InfluxDB service started successfully"
    else
        warn "InfluxDB service may not be running properly"
    fi
}

# Final setup and verification
final_setup() {
    log "Performing final setup..."
    
    # Set proper permissions for all created files
    chown -R "$SERVICE_USER:$SERVICE_USER" "$BACKUP_DIR" "$CONFIG_DIR" "$LOG_DIR"
    
    # Create initial backup
    log "Creating initial backup..."
    sudo -u "$SERVICE_USER" /usr/local/bin/influxdb-backup-scripts/backup/backup_full.sh || {
        warn "Initial backup failed - this is normal for new installations"
    }
    
    # Test backup listing
    log "Testing backup system..."
    sudo -u "$SERVICE_USER" /usr/local/bin/influxdb-backup-scripts/restore/list_backups.sh || {
        warn "Backup listing test failed - this is normal for new installations"
    }
    
    log "Final setup completed"
}

# Display completion message
display_completion() {
    echo
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}  Installation Completed Successfully!${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo
    echo -e "${BLUE}Next Steps:${NC}"
    echo "1. Configure InfluxDB initial setup:"
    echo "   influx setup --username admin --password <password> --org <org> --bucket <bucket> --retention 30d --force"
    echo
    echo "2. Test the backup system:"
    echo "   sudo -u $SERVICE_USER influxdb-backup-full"
    echo
    echo "3. Check service status:"
    echo "   systemctl status influxdb-backup.service"
    echo "   systemctl status influxdb-monitor.service"
    echo
    echo "4. View logs:"
    echo "   tail -f $LOG_DIR/backup.log"
    echo
    echo -e "${BLUE}Documentation:${NC}"
    echo "   See docs/ directory for detailed guides"
    echo
    echo -e "${BLUE}Backup Location:${NC}"
    echo "   $BACKUP_DIR"
    echo
    echo -e "${BLUE}Configuration:${NC}"
    echo "   $CONFIG_DIR"
    echo
    echo -e "${YELLOW}Important:${NC}"
    echo "   - Test backup and restore procedures"
    echo "   - Secure the encryption key"
    echo "   - Monitor backup logs regularly"
    echo "   - Keep multiple backup copies"
    echo
}

# Main installation function
main() {
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}  InfluxDB Backup & Restore Pipeline${NC}"
    echo -e "${BLUE}  Installation Script${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo
    
    check_root
    detect_os
    install_dependencies
    create_directories
    create_backup_user
    install_influxdb
    configure_influxdb
    setup_backup_scripts
    setup_systemd_services
    setup_cron_jobs
    setup_config_files
    generate_encryption_key
    start_influxdb
    final_setup
    display_completion
}

# Run main function
main "$@"
