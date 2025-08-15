FROM python:3.11-slim

# Install required packages
RUN apt-get update && apt-get install -y \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Install Python dependencies
RUN pip install --no-cache-dir \
    influxdb-client \
    requests \
    flask \
    schedule \
    psutil

# Create monitor user and directories
RUN useradd -m -s /bin/bash monitor \
    && mkdir -p /logs /config \
    && chown -R monitor:monitor /logs /config

# Copy monitoring scripts
COPY monitor.py /usr/local/bin/
COPY monitor.conf /etc/monitor.conf

# Make scripts executable
RUN chmod +x /usr/local/bin/*.py

# Switch to monitor user
USER monitor

# Set working directory
WORKDIR /home/monitor

# Expose monitoring port
EXPOSE 3000

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=30s --retries=3 \
    CMD curl -f http://localhost:3000/health || exit 1

# Default command
CMD ["python", "/usr/local/bin/monitor.py"]
