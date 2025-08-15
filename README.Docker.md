# InfluxDB Backup & Restore - Docker Setup

This document describes the Docker-based setup for the InfluxDB backup and restore system.

## 🐳 Docker Services Overview

The system consists of four main services:

1. **influxdb** - Main InfluxDB 2.7 instance
2. **backup** - Automated backup service with cron scheduling
3. **restore** - On-demand restore service
4. **monitor** - Health monitoring and alerting service

## 🚀 Quick Start

### Prerequisites
- Docker Engine 20.10+
- Docker Compose 2.0+
- At least 4GB RAM available
- 20GB+ free disk space

### 1. Clone and Setup
```bash
git clone <repository-url>
cd Automated-DB-backup-and-restore
```

### 2. Configure Environment
Edit the environment variables in `docker-compose.influxdb.yml`:
- Change default passwords and tokens
- Update organization and bucket names
- Set backup retention policies
- Configure alert email addresses

### 3. Start Services
```bash
# Start all services
docker compose -f docker-compose.influxdb.yml up -d

# Start only specific services
docker compose -f docker-compose.influxdb.yml up -d influxdb backup

# Start restore service when needed
docker compose -f docker-compose.influxdb.yml --profile restore up -d restore
```

### 4. Verify Setup
```bash
# Check service status
docker compose -f docker-compose.influxdb.yml ps

# View logs
docker compose -f docker-compose.influxdb.yml logs -f

# Test InfluxDB connection
curl http://localhost:8086/health
```

## 🔧 Service Configuration

### InfluxDB Service
- **Port**: 8086
- **Data Volume**: `influxdb_data`
- **Config Volume**: `influxdb_config`
- **Health Check**: HTTP health endpoint

### Backup Service
- **Dependencies**: InfluxDB (healthy)
- **Volumes**: 
  - `./backups` → `/backups`
  - `./remote` → `/remote`
  - `backup_logs` → `/var/log`
- **Features**: Automated cron jobs, compression, encryption

### Restore Service
- **Profile**: `restore` (only starts when needed)
- **Dependencies**: InfluxDB (healthy)
- **Volumes**: Read-only access to backups and remote storage

### Monitor Service
- **Port**: 3000
- **Features**: Health checks, metrics collection, alerting
- **Dependencies**: InfluxDB (healthy)

## 📊 Backup Operations

### Automatic Backups
```bash
# View backup service logs
docker compose -f docker-compose.influxdb.yml logs -f backup

# Check backup status
docker exec postgres-backup ls -la /backups
```

### Manual Backup
```bash
# Execute backup manually
docker exec postgres-backup /usr/local/bin/backup.sh
```

### Backup Types
- **Incremental**: Daily backups (retention: 30 days)
- **Full**: Weekly backups (retention: 365 days)
- **Compression**: Gzip compression for space efficiency
- **Encryption**: AES-256 encryption for security

## 🔄 Restore Operations

### List Available Backups
```bash
# Start restore service
docker compose -f docker-compose.influxdb.yml --profile restore up -d restore

# List backups
docker exec influxdb-restore /usr/local/bin/list_backups.sh
```

### Restore Database
```bash
# Execute restore
docker exec influxdb-restore /usr/local/bin/restore.sh <backup-file>
```

## 📈 Monitoring

### Service Health
```bash
# Check all service health
docker compose -f docker-compose.influxdb.yml ps

# View monitor logs
docker compose -f docker-compose.influxdb.yml logs monitor
```

### Metrics Dashboard
- Access monitoring dashboard at `http://localhost:3000`
- View backup statistics and system health
- Configure alert thresholds

## 🛠️ Maintenance

### Update Services
```bash
# Pull latest images
docker compose -f docker-compose.influxdb.yml pull

# Rebuild and restart
docker compose -f docker-compose.influxdb.yml up -d --build
```

### Backup Cleanup
```bash
# Clean old backups
docker exec influxdb-backup /usr/local/bin/cleanup_old_backups.sh
```

### Log Rotation
```bash
# View log sizes
docker exec influxdb-backup du -sh /var/log/*
```

## 🔒 Security Features

- **Network Isolation**: All services on private `appnet` bridge
- **User Separation**: Each service runs as non-root user
- **Volume Security**: Read-only mounts where appropriate
- **Token Authentication**: InfluxDB token-based access
- **Encrypted Backups**: AES-256 encryption for backup files

## 🚨 Troubleshooting

### Common Issues

#### Service Won't Start
```bash
# Check service logs
docker compose -f docker-compose.influxdb.yml logs <service-name>

# Verify dependencies
docker compose -f docker-compose.influxdb.yml config
```

#### Backup Failures
```bash
# Check backup service status
docker exec influxdb-backup systemctl status cron

# Verify InfluxDB connectivity
docker exec influxdb-backup influx ping
```

#### Restore Issues
```bash
# Check backup file integrity
docker exec influxdb-restore ls -la /backups/

# Verify restore permissions
docker exec influxdb-restore id
```

### Health Checks
```bash
# Manual health check
docker exec influxdb-backup pgrep -f backup

# Service health status
docker compose -f docker-compose.influxdb.yml ps
```

## 📁 Volume Management

### Persistent Data
- **influxdb_data**: Database files
- **influxdb_config**: Configuration files
- **backup_logs**: Backup service logs
- **restore_logs**: Restore service logs

### Backup Storage
- **./backups**: Local backup storage
- **./remote**: Remote backup storage (if configured)

## 🔄 Migration from PostgreSQL

If migrating from the PostgreSQL setup:

1. **Stop PostgreSQL services**
   ```bash
   docker compose down
   ```

2. **Backup existing data**
   ```bash
   docker exec postgres-db pg_dumpall > postgres_backup.sql
   ```

3. **Start InfluxDB services**
   ```bash
   docker compose -f docker-compose.influxdb.yml up -d
   ```

4. **Migrate data** (requires custom migration script)

## 📚 Additional Resources

- [InfluxDB Documentation](https://docs.influxdata.com/)
- [Docker Compose Reference](https://docs.docker.com/compose/)
- [Backup Best Practices](docs/backup_restore.md)
- [Security Hardening](docs/security.md)

## 🤝 Support

For Docker-specific issues:
1. Check service logs: `docker compose logs <service>`
2. Verify configuration: `docker compose config`
3. Test connectivity: `docker exec <container> <command>`
4. Review this documentation
5. Open an issue on GitHub

---

**Docker Compose Version**: 3.8
**InfluxDB Version**: 2.7
**Last Updated**: $(date)
**Compatibility**: Docker 20.10+, Docker Compose 2.0+
