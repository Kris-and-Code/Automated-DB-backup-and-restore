#!/bin/bash

# InfluxDB List Backups Script
# Lists all available backup files with details

set -e

# Default values
BACKUP_DIR="/backups"
REMOTE_DIR="/remote"
DETAILED="${1:-false}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Print header
print_header() {
    echo -e "${BLUE}=== InfluxDB Backup Inventory ===${NC}"
    echo ""
}

# Print backup details
print_backup_details() {
    local file="$1"
    local location="$2"
    
    if [ "$DETAILED" = "true" ] || [ "$DETAILED" = "detailed" ]; then
        # Get detailed information
        local size=$(du -h "$file" | cut -f1)
        local date=$(stat -c%y "$file" | cut -d' ' -f1)
        local time=$(stat -c%y "$file" | cut -d' ' -f2 | cut -d'.' -f1)
        local permissions=$(stat -c%a "$file")
        local owner=$(stat -c%U "$file")
        
        echo -e "  ${GREEN}$(basename "$file")${NC}"
        echo -e "    Location: $location"
        echo -e "    Size: $size"
        echo -e "    Date: $date $time"
        echo -e "    Permissions: $permissions"
        echo -e "    Owner: $owner"
        
        # Check if encrypted
        if [[ "$file" == *.enc ]]; then
            echo -e "    ${YELLOW}Status: Encrypted${NC}"
        else
            echo -e "    ${GREEN}Status: Unencrypted${NC}"
        fi
        
        echo ""
    else
        # Simple format
        local size=$(du -h "$file" | cut -f1)
        local date=$(stat -c%y "$file" | cut -d' ' -f1)
        echo -e "  ${GREEN}$(basename "$file")${NC} - $size - $date"
    fi
}

# List backups from directory
list_directory_backups() {
    local dir="$1"
    local location="$2"
    
    if [ ! -d "$dir" ]; then
        echo -e "${RED}Directory not found: $dir${NC}"
        return
    fi
    
    local backup_files=$(find "$dir" -name "influxdb_*.tar.gz*" -type f 2>/dev/null | sort)
    
    if [ -z "$backup_files" ]; then
        echo -e "${YELLOW}No backups found in $location${NC}"
        return
    fi
    
    echo -e "${BLUE}$location Backups:${NC}"
    echo "$backup_files" | while read -r file; do
        print_backup_details "$file" "$location"
    done
}

# Get backup statistics
get_statistics() {
    echo -e "${BLUE}=== Backup Statistics ===${NC}"
    
    # Count local backups
    local local_count=0
    local local_size=0
    if [ -d "$BACKUP_DIR" ]; then
        local_count=$(find "$BACKUP_DIR" -name "influxdb_*.tar.gz*" -type f 2>/dev/null | wc -l)
        local_size=$(du -sh "$BACKUP_DIR" 2>/dev/null | cut -f1 || echo "0")
    fi
    
    # Count remote backups
    local remote_count=0
    local remote_size=0
    if [ -d "$REMOTE_DIR" ]; then
        remote_count=$(find "$REMOTE_DIR" -name "influxdb_*.tar.gz*" -type f 2>/dev/null | wc -l)
        remote_size=$(du -sh "$REMOTE_DIR" 2>/dev/null | cut -f1 || echo "0")
    fi
    
    local total_count=$((local_count + remote_count))
    
    echo -e "Total Backups: ${GREEN}$total_count${NC}"
    echo -e "  Local: ${BLUE}$local_count${NC} (Size: $local_size)"
    echo -e "  Remote: ${BLUE}$remote_count${NC} (Size: $remote_size)"
    echo ""
}

# Analyze backup types
analyze_backup_types() {
    echo -e "${BLUE}=== Backup Type Analysis ===${NC}"
    
    # Count by type
    local incremental_count=0
    local full_count=0
    local encrypted_count=0
    
    # Check local directory
    if [ -d "$BACKUP_DIR" ]; then
        incremental_count=$(find "$BACKUP_DIR" -name "influxdb_incremental_*.tar.gz*" -type f 2>/dev/null | wc -l)
        full_count=$(find "$BACKUP_DIR" -name "influxdb_full_*.tar.gz*" -type f 2>/dev/null | wc -l)
        encrypted_count=$(find "$BACKUP_DIR" -name "*.enc" -type f 2>/dev/null | wc -l)
    fi
    
    # Check remote directory
    if [ -d "$REMOTE_DIR" ]; then
        incremental_count=$((incremental_count + $(find "$REMOTE_DIR" -name "influxdb_incremental_*.tar.gz*" -type f 2>/dev/null | wc -l)))
        full_count=$((full_count + $(find "$REMOTE_DIR" -name "influxdb_full_*.tar.gz*" -type f 2>/dev/null | wc -l)))
        encrypted_count=$((encrypted_count + $(find "$REMOTE_DIR" -name "*.enc" -type f 2>/dev/null | wc -l)))
    fi
    
    echo -e "Incremental Backups: ${GREEN}$incremental_count${NC}"
    echo -e "Full Backups: ${GREEN}$full_count${NC}"
    echo -e "Encrypted Backups: ${YELLOW}$encrypted_count${NC}"
    echo ""
}

# Check backup health
check_backup_health() {
    echo -e "${BLUE}=== Backup Health Check ===${NC}"
    
    local issues=0
    
    # Check for very old backups (over 1 year)
    local old_backups=$(find "$BACKUP_DIR" "$REMOTE_DIR" -name "influxdb_*.tar.gz*" -type f -mtime +365 2>/dev/null | wc -l)
    if [ "$old_backups" -gt 0 ]; then
        echo -e "${YELLOW}Warning: $old_backups backups are over 1 year old${NC}"
        issues=$((issues + 1))
    fi
    
    # Check for very large backups (over 1GB)
    local large_backups=$(find "$BACKUP_DIR" "$REMOTE_DIR" -name "influxdb_*.tar.gz*" -type f -size +1G 2>/dev/null | wc -l)
    if [ "$large_backups" -gt 0 ]; then
        echo -e "${YELLOW}Info: $large_backups backups are over 1GB${NC}"
    fi
    
    # Check for recent backups (within last 24 hours)
    local recent_backups=$(find "$BACKUP_DIR" "$REMOTE_DIR" -name "influxdb_*.tar.gz*" -type f -mtime -1 2>/dev/null | wc -l)
    if [ "$recent_backups" -eq 0 ]; then
        echo -e "${RED}Warning: No backups created in the last 24 hours${NC}"
        issues=$((issues + 1))
    else
        echo -e "${GREEN}Recent backups: $recent_backups created in last 24 hours${NC}"
    fi
    
    if [ "$issues" -eq 0 ]; then
        echo -e "${GREEN}Backup health: Good${NC}"
    else
        echo -e "${YELLOW}Backup health: $issues issues detected${NC}"
    fi
    echo ""
}

# Main execution
main() {
    print_header
    
    # List backups from both directories
    list_directory_backups "$BACKUP_DIR" "Local"
    echo ""
    list_directory_backups "$REMOTE_DIR" "Remote"
    echo ""
    
    # Show statistics
    get_statistics
    
    # Analyze backup types
    analyze_backup_types
    
    # Check backup health
    check_backup_health
    
    # Show usage information
    if [ "$DETAILED" != "true" ] && [ "$DETAILED" != "detailed" ]; then
        echo -e "${BLUE}For detailed information, run:${NC}"
        echo -e "  $0 detailed"
        echo ""
    fi
    
    echo -e "${BLUE}To restore a backup, use:${NC}"
    echo -e "  restore.sh <backup-filename>"
    echo ""
}

# Run main function
main "$@"
