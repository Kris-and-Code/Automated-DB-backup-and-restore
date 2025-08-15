FROM ubuntu:22.04

# Install required packages
RUN apt-get update && apt-get install -y \
    curl \
    wget \
    gzip \
    openssl \
    python3 \
    python3-pip \
    python3-requests \
    && rm -rf /var/lib/apt/lists/*

# Install InfluxDB CLI
RUN wget https://dl.influxdata.com/influxdb/releases/influxdb2-client-2.7.1-linux-amd64.tar.gz \
    && tar xvzf influxdb2-client-2.7.1-linux-amd64.tar.gz \
    && cp influxdb2-client-2.7.1-linux-amd64/influx /usr/local/bin/ \
    && rm -rf influxdb2-client-2.7.1-linux-amd64*

# Create restore user and directories
RUN useradd -m -s /bin/bash restore \
    && mkdir -p /backups /remote /var/log /scripts \
    && chown -R restore:restore /backups /remote /var/log /scripts

# Copy restore scripts
COPY restore.sh /usr/local/bin/
COPY list_backups.sh /usr/local/bin/

# Make scripts executable
RUN chmod +x /usr/local/bin/*.sh

# Switch to restore user
USER restore

# Set working directory
WORKDIR /home/restore

# Health check
HEALTHCHECK --interval=60s --timeout=10s --start-period=60s --retries=3 \
    CMD pgrep -f restore || exit 1

# Default command
CMD ["/bin/bash"]
