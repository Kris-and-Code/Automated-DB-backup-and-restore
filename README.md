# Automated Database Backup & Restore Pipeline for InfluxDB 2

This project provides a complete automated solution for backing up and restoring InfluxDB 2 instances with security, compression, and monitoring capabilities.

## 🏗️ System Architecture

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   InfluxDB 2   │    │  Backup Scripts │    │  Restore Script │
│   Instance      │◄──►│  (Daily/Full)   │◄──►│  (On-Demand)    │
└─────────────────┘    └─────────────────┘    └─────────────────┘
         │                       │                       │
         │                       ▼                       ▼
         │              ┌─────────────────┐    ┌─────────────────┐
         │              │  Compression    │    │  Systemd        │
         │              │  & Encryption   │    │  Services       │
         └──────────────►└─────────────────┘    └─────────────────┘
                                │                       │
                                ▼                       ▼
                       ┌─────────────────┐    ┌─────────────────┐
                       │  Backup Storage │    │  Cron Jobs      │
                       │  (Encrypted)    │    │  (Scheduling)   │
                       └─────────────────┘    └─────────────────┘
```

## 🚀 Features

- **Automated Backups**: Daily incremental and weekly full backups
- **Data Compression**: Gzip compression to save storage space
- **Encryption**: AES-256 encryption for backup security
- **Monitoring**: Systemd services with health checks
- **Scheduling**: Cron-based automation
- **Security**: Hardened InfluxDB configuration
- **Recovery**: One-click restore from any backup

## 📁 Project Structure

```
├── scripts/
│   ├── install/
│   │   ├── install_influxdb.sh          # InfluxDB installation
│   │   ├── configure_influxdb.sh        # Security configuration
│   │   └── setup_backup_user.sh         # Backup user creation
│   ├── backup/
│   │   ├── backup_incremental.sh        # Daily incremental backup
│   │   ├── backup_full.sh               # Weekly full backup
│   │   └── backup_utils.sh              # Common backup functions
│   ├── restore/
│   │   ├── restore_database.sh          # Database restore script
│   │   └── list_backups.sh              # Backup listing utility
│   └── maintenance/
│       ├── cleanup_old_backups.sh       # Backup retention management
│       └── verify_backup.sh             # Backup integrity check
├── config/
│   ├── influxdb.conf                    # InfluxDB configuration
│   ├── backup.conf                      # Backup configuration
│   └── security.conf                    # Security settings
├── systemd/
│   ├── influxdb-backup.service          # Backup service
│   ├── influxdb-restore.service         # Restore service
│   └── influxdb-monitor.service         # Health monitoring
├── cron/
│   └── backup_crontab                   # Cron job definitions
├── docs/
│   ├── installation.md                  # Installation guide
│   ├── configuration.md                 # Configuration guide
│   ├── backup_restore.md               # Backup/restore procedures
│   ├── security.md                      # Security hardening
│   └── troubleshooting.md               # Troubleshooting guide
├── tests/
│   ├── test_backup.sh                   # Backup testing
│   └── test_restore.sh                  # Restore testing
├── install.sh                           # Main installation script
├── uninstall.sh                         # Cleanup script
└── README.md                            # This file
```

## 🛠️ Prerequisites

- Linux server (Ubuntu 20.04+ or CentOS 8+)
- Root or sudo access
- Minimum 4GB RAM
- 20GB+ free disk space
- Internet connection for package installation

## 📦 Quick Installation

```bash
# Clone the repository
git clone <repository-url>
cd Automated-DB-backup-and-restore

# Run the main installation script
sudo ./install.sh
```

## 🔧 Manual Installation Steps

1. **Install InfluxDB 2**
   ```bash
   sudo ./scripts/install/install_influxdb.sh
   ```

2. **Configure Security**
   ```bash
   sudo ./scripts/install/configure_influxdb.sh
   ```

3. **Setup Backup User**
   ```bash
   sudo ./scripts/install/setup_backup_user.sh
   ```

4. **Configure Backup System**
   ```bash
   sudo ./scripts/backup/backup_utils.sh
   ```

5. **Enable Services**
   ```bash
   sudo systemctl enable influxdb-backup.service
   sudo systemctl enable influxdb-monitor.service
   ```

## 📊 Backup Configuration

### Backup Types
- **Incremental**: Daily backups of new/modified data
- **Full**: Weekly complete database snapshots
- **Compression**: Gzip compression (typically 70-80% space savings)
- **Encryption**: AES-256 encryption with secure key management

### Retention Policy
- Incremental backups: 30 days
- Full backups: 12 months
- Compressed backups: 24 months
- Automatic cleanup of expired backups

## 🔒 Security Features

- **TLS/SSL**: Encrypted communication
- **Authentication**: Token-based access control
- **Backup Encryption**: AES-256 encryption
- **Access Control**: Limited backup user permissions
- **Network Security**: Firewall rules and IP restrictions

## 📈 Monitoring & Health Checks

- **Service Status**: Systemd service monitoring
- **Backup Health**: Automated backup verification
- **Storage Monitoring**: Disk space and backup size tracking
- **Alert System**: Email notifications for failures

## 🚨 Troubleshooting

Common issues and solutions are documented in `docs/troubleshooting.md`:

- Backup failures
- Restore issues
- Performance problems
- Security concerns
- Service startup issues

## 📚 Documentation

- [Installation Guide](docs/installation.md)
- [Configuration Guide](docs/configuration.md)
- [Backup & Restore Procedures](docs/backup_restore.md)
- [Security Hardening](docs/security.md)
- [Troubleshooting](docs/troubleshooting.md)

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly
5. Submit a pull request

## 📄 License

This project is licensed under the MIT License - see the LICENSE file for details.

## ⚠️ Disclaimer

This system is designed for production use but should be thoroughly tested in your specific environment before deployment. Always maintain multiple backup copies and test restore procedures regularly.



---

**Last Updated**: $(20.08.2025)
**Version**: 1.0.0
**Compatibility**: InfluxDB 2.x, Linux (Ubuntu/CentOS)

