#!/usr/bin/env bash

set -e

# Load the mev-commit version from environment
source /etc/environment

# Configuration Variables
APP_NAME="mev-commit"
ENVIRONMENT="${ENVIRONMENT:-production}"
VERSION="${MEV_COMMIT_VERSION:-unknown}"
LOG_FORMAT="${MEV_COMMIT_LOG_FMT:-json}"
LOG_LEVEL_INFO="INFO"
LOG_LEVEL_ERROR="ERROR"

# Log Functions
log_info() {
  echo '{
    "timestamp": "'"$(date --iso-8601=seconds)"'",
    "level": "'"$LOG_LEVEL_INFO"'",
    "app": "'"$APP_NAME"'",
    "environment": "'"$ENVIRONMENT"'",
    "version": "'"$VERSION"'",
    "message": "'"$1"'"
  }'
}

log_error() {
  echo '{
    "timestamp": "'"$(date --iso-8601=seconds)"'",
    "level": "'"$LOG_LEVEL_ERROR"'",
    "app": "'"$APP_NAME"'",
    "environment": "'"$ENVIRONMENT"'",
    "version": "'"$VERSION"'",
    "message": "'"$1"'"
  }' >&2
}

# Print the mev-commit version
log_info "Running mev-commit version: ${MEV_COMMIT_VERSION}"

# Set variables based on DOMAIN
RPC_URL="wss://chainrpc-wss.${DOMAIN}"
BOOTNODE="/dnsaddr/bootnode.${DOMAIN}"
CONTRACTS_URL="https://contracts.${DOMAIN}"

# Fetch contracts.json and export necessary environment variables
contracts_json=$(curl -sL "${CONTRACTS_URL}")
if ! echo "${contracts_json}" | jq . > /dev/null 2>&1; then
    log_error "Failed to fetch contracts from ${CONTRACTS_URL}"
    exit 1
fi

export MEV_COMMIT_BLOCK_TRACKER_ADDR=$(echo "${contracts_json}" | jq -r '.BlockTracker')
export MEV_COMMIT_BIDDER_REGISTRY_ADDR=$(echo "${contracts_json}" | jq -r '.BidderRegistry')
export MEV_COMMIT_PRECONF_ADDR=$(echo "${contracts_json}" | jq -r '.PreconfManager')
export MEV_COMMIT_LOG_FMT="${MEV_COMMIT_LOG_FMT:-json}"

# Check if PRIVATE_KEY_BIDDER is set
if [ -z "${PRIVATE_KEY_BIDDER}" ]; then
  log_error "PRIVATE_KEY_BIDDER environment variable is not set"
  exit 1
else
  log_info "PRIVATE_KEY_BIDDER is set."
  # Write the private key to key
  echo "${PRIVATE_KEY_BIDDER}" > "${ROOT_PATH}/key"
  # Secure the key file by restricting permissions
  chmod 600 "${ROOT_PATH}/key"
  # Export MEV_COMMIT_PRIVKEY_FILE to point to the key file
  export MEV_COMMIT_PRIVKEY_FILE="${ROOT_PATH}/key"
fi

# Define flags for mev-commit
FLAGS=(
    --settlement-ws-rpc-endpoint "${RPC_URL}"
    --peer-type "bidder"
    --bootnodes "${BOOTNODE}"
    --log-tags "service:docker-mev-commit-bidder"
    --bidder-bid-timeout "15s"  # Override timeout here
)

# Start mev-commit in the background
${BINARY_PATH} "${FLAGS[@]}" &

PID=$!

# Function to wait for mev-commit to be ready
wait_for_health() {
    log_info "Waiting for mev-commit to be ready..."
    until curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:13523/health | grep -q 200; do
        sleep 1
    done
    log_info "mev-commit is ready."
}

# Function to send auto deposit request
send_auto_deposit() {
    log_info "Sending auto deposit request..."
    response=$(curl --silent --show-error --output /dev/null --write-out "%{http_code}" --request POST "http://127.0.0.1:13523/v1/bidder/auto_deposit/${AUTO_DEPOSIT_VALUE}")
    if [ "${response}" -ne 200 ]; then
        log_error "Failed to send auto deposit request, status code: ${response}"
    else
        log_info "Auto deposit request sent successfully"
    fi
}

# Wait for mev-commit to be ready
wait_for_health

# Send auto deposit request once
send_auto_deposit

# Trap to handle script termination and clean up background jobs
trap "log_info 'Received termination signal. Exiting...'; kill ${PID}; kill 0; exit 0" SIGINT SIGTERM

# Wait for mev-commit process to exit
wait ${PID}
