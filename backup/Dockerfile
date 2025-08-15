FROM ubuntu:22.04

# Prevent interactive prompts during package installation
ENV DEBIAN_FRONTEND=noninteractive

# Install required packages
RUN apt-get update && apt-get install -y \
    postgresql-client \
    cron \
    rsync \
    gzip \
    curl \
    vim \
    && rm -rf /var/lib/apt/lists/*

# Create necessary directories
RUN mkdir -p /backups /remote /scripts /var/log/cron

# Copy scripts
COPY backup.sh /scripts/
COPY restore.sh /scripts/
COPY crontab.txt /tmp/crontab.txt

# Make scripts executable
RUN chmod +x /scripts/backup.sh /scripts/restore.sh

# Set up cron
RUN crontab /tmp/crontab.txt

# Create log file
RUN touch /var/log/cron.log

# Copy entrypoint script
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Set working directory
WORKDIR /scripts

# Expose port for potential health checks
EXPOSE 8080

# Health check - use a simple command that doesn't require PostgreSQL connection
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD pg_isready --version || exit 1

ENTRYPOINT ["/entrypoint.sh"]
