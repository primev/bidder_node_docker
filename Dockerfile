# Use Ubuntu 20.04 as the base image
FROM ubuntu:20.04

# Install necessary utilities
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    jq \
    sudo \
    ca-certificates \
    tini \
    && rm -rf /var/lib/apt/lists/*

# Copy the entrypoint script into the image
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Use tini as the init system
ENTRYPOINT ["/usr/bin/tini", "--", "/entrypoint.sh"]