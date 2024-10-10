#!/usr/bin/env bash

set -e

# Set variables based on DOMAIN
RPC_URL="wss://chainrpc-wss.${DOMAIN}"
BOOTNODE="/dnsaddr/bootnode.${DOMAIN}"
CONTRACTS_URL="https://contracts.${DOMAIN}"

# Fetch contracts.json and export necessary environment variables
contracts_json=$(curl -sL "${CONTRACTS_URL}")
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
fi

# Export the private key so that mev-commit can access it
export MEV_COMMIT_PRIVATE_KEY="${PRIVATE_KEY_BIDDER}"

# Define flags for mev-commit
FLAGS=(
    --settlement-ws-rpc-endpoint "${RPC_URL}"
    --peer-type "bidder"
    --bootnodes "${BOOTNODE}"
    --log-tags "service:docker-mev-commit-bidder"
)

# Start mev-commit in the background
"${BINARY_PATH}" "${FLAGS[@]}" &

PID=$!

# Function to wait for mev-commit to be ready
wait_for_health() {
    echo "Waiting for mev-commit to be ready..."
    until curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:13523/health | grep -q 200; do
        sleep 1
    done
    echo "mev-commit is ready."
}

# Function to send auto deposit request until successful
send_auto_deposit_until_successful() {
    while true; do
        echo "Sending auto deposit request..."
        response=$(curl --silent --show-error --fail --output /dev/null --write-out "%{http_code}" \
            --request POST "http://127.0.0.1:13523/v1/bidder/auto_deposit/1000000000000000000")

        if [ "${response}" -eq 200 ]; then
            echo "Auto deposit request sent successfully"
            break  # Exit the loop when successful
        else
            echo "Failed to send auto deposit request, status code: ${response}"
            echo "Retrying auto deposit in 30 seconds..."
            sleep 30  # Wait for 30 seconds before the next attempt
        fi
    done
}

# Wait for mev-commit to be ready
wait_for_health

# Start auto-deposit process
send_auto_deposit_until_successful &

# Trap to handle script termination and clean up background jobs
trap "echo 'Received termination signal. Exiting...'; kill ${PID}; kill 0; exit 0" SIGINT SIGTERM

# Wait for mev-commit process to exit
wait ${PID}
