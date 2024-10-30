# Use Ubuntu 20.04 as the base image
FROM ubuntu:20.04

# Install necessary utilities
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    jq \
    ca-certificates \
    tini \
    && rm -rf /var/lib/apt/lists/*

# Set default environment variables
ENV ROOT_PATH=/opt/mev-commit
ENV BINARY_PATH=${ROOT_PATH}/mev-commit
ENV DOMAIN=testnet.mev-commit.xyz
ENV ARTIFACTS_URL=https://github.com/primev/mev-commit/releases/latest/download

# Create the directory for mev-commit
RUN mkdir -p ${ROOT_PATH}
WORKDIR ${ROOT_PATH}

# Download and install the latest mev-commit binary
RUN VERSION=$(curl -sIL -o /dev/null -w %{url_effective} https://github.com/primev/mev-commit/releases/latest | sed 's:.*/::' | sed 's/^v//') \
    && echo "Latest version: $VERSION" \
    && FILE="mev-commit_${VERSION}_Linux_x86_64.tar.gz" \
    && echo "Downloading $FILE" \
    && curl -sL "${ARTIFACTS_URL}/${FILE}" -o "${FILE}" \
    && tar -xzf "${FILE}" -C "${ROOT_PATH}" \
    && chmod +x ${BINARY_PATH} \
    && echo "export MEV_COMMIT_VERSION=${VERSION}" >> /etc/environment

# Expose http port. Not sure if actuallly needed
EXPOSE 13523

# Copy the entrypoint script into the image
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Use tini as the init system
ENTRYPOINT ["/usr/bin/tini", "--", "/entrypoint.sh"]
