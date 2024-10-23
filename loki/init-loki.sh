#!/bin/bash
set -e

# Create necessary directories with proper permissions
mkdir -p /loki/index/uploader
mkdir -p /loki/chunks
mkdir -p /wal
mkdir -p /data

# Ensure ownership of directories
chown -R loki:loki /loki
chown -R loki:loki /wal
chown -R loki:loki /data

echo "Loki directories initialized."

# Execute the original Loki binary as the loki user
exec su-exec loki /usr/bin/loki "$@"
