#!/usr/bin/env bash

set -e

# Set variables based on DOMAIN
RPC_URL="wss://chainrpc-wss.${DOMAIN}"
BOOTNODE="/dnsaddr/bootnode.${DOMAIN}"
CONTRACTS_URL="https://contracts.${DOMAIN}"

# Fetch contracts.json and export necessary environment variables
contracts_json=$(curl -sL ${CONTRACTS_URL})
if ! echo "${contracts_json}" | jq . > /dev/null 2>&1; then
    echo "Failed to fetch contracts from ${CONTRACTS_URL}"
    exit 1
fi

export MEV_COMMIT_BLOCK_TRACKER_ADDR=$(echo "${contracts_json}" | jq -r '.BlockTracker')
export MEV_COMMIT_BIDDER_REGISTRY_ADDR=$(echo "${contracts_json}" | jq -r '.BidderRegistry')
export MEV_COMMIT_PRECONF_ADDR=$(echo "${contracts_json}" | jq -r '.PreconfManager')

# Check if PRIVATE_KEY_BIDDER is set
if [ -z "${PRIVATE_KEY_BIDDER}" ]; then
  echo "PRIVATE_KEY_BIDDER environment variable is not set"
  exit 1
else
  echo "PRIVATE_KEY_BIDDER is set."
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
    # Optionally, you can specify the priv-key-file flag here
    # --priv-key-file "${ROOT_PATH}/key"
)

# Start mev-commit in the background
${BINARY_PATH} "${FLAGS[@]}" &

PID=$!

# Function to wait for mev-commit to be ready
wait_for_health() {
    echo "Waiting for mev-commit to be ready..."
    until curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:13523/health | grep -q 200; do
        sleep 1
    done
    echo "mev-commit is ready."
}

# Function to send auto deposit request
send_auto_deposit() {
    echo "Sending auto deposit request..."
    response=$(curl --silent --show-error --output /dev/null --write-out "%{http_code}" --request POST "http://127.0.0.1:13523/v1/bidder/auto_deposit/1000000000000000000")
    if [ "${response}" -ne 200 ]; then
        echo "Failed to send auto deposit request, status code: ${response}"
    else
        echo "Auto deposit request sent successfully"
    fi
}

# Wait for mev-commit to be ready
wait_for_health

# Run auto-deposit continuously
while true; do
    send_auto_deposit
    sleep 30  # Wait for 30 seconds before the next attempt
done &

# Trap to handle script termination and clean up background jobs
trap "echo 'Received termination signal. Exiting...'; kill ${PID}; kill 0; exit 0" SIGINT SIGTERM

# Wait for mev-commit process to exit
wait ${PID}
