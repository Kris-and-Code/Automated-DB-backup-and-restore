#!/bin/bash

# Switch to InfluxDB Setup Script
# This script helps migrate from PostgreSQL to InfluxDB setup

set -e

echo "🔄 Switching from PostgreSQL to InfluxDB setup..."

# Check if Docker is running
if ! docker info >/dev/null 2>&1; then
    echo "❌ Docker is not running. Please start Docker first."
    exit 1
fi

# Check if docker-compose.influxdb.yml exists
if [ ! -f "docker-compose.influxdb.yml" ]; then
    echo "❌ docker-compose.influxdb.yml not found. Please ensure you have the InfluxDB setup files."
    exit 1
fi

# Stop PostgreSQL services if running
echo "🛑 Stopping PostgreSQL services..."
if docker compose ps | grep -q "postgres"; then
    docker compose down
    echo "✅ PostgreSQL services stopped."
else
    echo "ℹ️  No PostgreSQL services running."
fi

# Backup existing PostgreSQL data if exists
if [ -d "db" ] && [ -f "docker-compose.yml" ]; then
    echo "💾 Creating backup of existing PostgreSQL setup..."
    cp docker-compose.yml docker-compose.postgresql.yml.backup
    echo "✅ PostgreSQL compose file backed up as docker-compose.postgresql.yml.backup"
fi

# Create necessary directories
echo "📁 Creating necessary directories..."
mkdir -p backups remote logs config

# Set proper permissions
echo "🔐 Setting proper permissions..."
chmod 755 backups remote logs config

# Start InfluxDB services
echo "🚀 Starting InfluxDB services..."
docker compose -f docker-compose.influxdb.yml up -d

# Wait for services to be healthy
echo "⏳ Waiting for services to be healthy..."
sleep 30

# Check service status
echo "📊 Checking service status..."
docker compose -f docker-compose.influxdb.yml ps

# Test InfluxDB connection
echo "🧪 Testing InfluxDB connection..."
if curl -s http://localhost:8086/health >/dev/null; then
    echo "✅ InfluxDB is running and healthy!"
else
    echo "❌ InfluxDB health check failed. Check logs with: docker compose -f docker-compose.influxdb.yml logs influxdb"
fi

echo ""
echo "🎉 Migration to InfluxDB setup completed!"
echo ""
echo "📋 Next steps:"
echo "1. Access InfluxDB UI at: http://localhost:8086"
echo "2. Login with: admin / adminpassword"
echo "3. View backup service logs: docker compose -f docker-compose.influxdb.yml logs -f backup"
echo "4. Check monitoring dashboard: http://localhost:3000"
echo ""
echo "📚 For more information, see: README.Docker.md"
echo ""
echo "🔄 To switch back to PostgreSQL:"
echo "   docker compose -f docker-compose.postgresql.yml.backup up -d"
