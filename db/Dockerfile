FROM postgres:15-alpine

# Set environment variables
ENV POSTGRES_USER=devuser
ENV POSTGRES_PASSWORD=devpass
ENV POSTGRES_DB=devdb

# Create a directory for initialization scripts
RUN mkdir -p /docker-entrypoint-initdb.d

# Copy initialization script
COPY init.sql /docker-entrypoint-initdb.d/

# Expose PostgreSQL port
EXPOSE 5432

# Set proper permissions
RUN chown -R postgres:postgres /var/lib/postgresql/data

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD pg_isready -U devuser -d devdb || exit 1
