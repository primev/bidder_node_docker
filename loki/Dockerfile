FROM grafana/loki:2.8.2

# Switch to root to perform privileged operations
USER root

# Update package lists and install necessary packages
RUN apk update && \
    apk add --no-cache bash su-exec

# Copy the initialization script with executable permissions
COPY --chmod=755 init-loki.sh /init-loki.sh

# Create necessary directories and set ownership
RUN mkdir -p /loki /wal && \
    chown -R loki:loki /loki /wal

# Set the entrypoint to the initialization script
ENTRYPOINT ["/init-loki.sh"]

# Set the default command to start Loki with the configuration file
CMD ["-config.file=/etc/loki/config.yaml"]
