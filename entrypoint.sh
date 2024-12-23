#!/usr/bin/env bash

set -e

###############################################################################
# 1) Source .env if it exists
###############################################################################
load_env_file() {
  local env_file="$1"
  if [ -f "$env_file" ]; then
    echo "Loading environment variables from $env_file"
    # shellcheck disable=SC1090,SC1091
    set -o allexport
    source "$env_file"
    set +o allexport
  fi
}

# Load .env from same directory as the script
load_env_file "$(dirname "$(realpath "$0")")/.env"

###############################################################################
# 2) Set defaults
###############################################################################
APP_NAME="mev-commit"
ENVIRONMENT="${ENVIRONMENT:-production}"
MEV_COMMIT_VERSION="${MEV_COMMIT_VERSION:-unknown}"
DOMAIN="${DOMAIN:-testnet.mev-commit.xyz}"
AUTO_DEPOSIT_VALUE="${AUTO_DEPOSIT_VALUE:-300000000000000000}"  # Default 0.3 ETH
BINARY_PATH="${BINARY_PATH:-/usr/local/bin/mev-commit}"
ARTIFACTS_BASE_URL="https://github.com/primev/mev-commit/releases"
RPC_URL="${RPC_URL:-wss://chainrpc-wss.${DOMAIN}}"

# Logging
LOG_FMT="${LOG_FMT:-json}"
LOG_LEVEL="${LOG_LEVEL:-info}"

# For mev-commit >= v0.8.0, we must pass a file to --priv-key-file.
# We'll use an in-memory file descriptor so the key never touches disk.
PRIV_KEY_FD="/proc/self/fd/3"

echo "Using RPC_URL=${RPC_URL}"

###############################################################################
# 3) (Optional) Download mev-commit if needed
###############################################################################
INSTALLED_VERSION=""
if command -v "${BINARY_PATH}" &> /dev/null; then
  INSTALLED_VERSION=$("${BINARY_PATH}" --version 2>/dev/null | awk '{print $3}')
  echo "Installed mev-commit version: ${INSTALLED_VERSION}"
fi

if [ "${MEV_COMMIT_VERSION}" = "unknown" ]; then
  LATEST_VERSION=$(curl -sIL -o /dev/null -w %{url_effective} \
    https://github.com/primev/mev-commit/releases/latest \
    | sed 's:.*/::' | sed 's/^v//')
  echo "Latest mev-commit version: ${LATEST_VERSION}"
else
  LATEST_VERSION=${MEV_COMMIT_VERSION}
  echo "Using mev-commit version: ${LATEST_VERSION}"
fi

# Download if not installed or if the version is out of date
if [ -z "${INSTALLED_VERSION}" ] || [ "${INSTALLED_VERSION}" != "${LATEST_VERSION}" ]; then
  echo "Downloading mev-commit ${LATEST_VERSION}..."
  FILE="mev-commit_${LATEST_VERSION}_Linux_x86_64.tar.gz"
  DOWNLOAD_URL="${ARTIFACTS_BASE_URL}/download/v${LATEST_VERSION}/${FILE}"
  TEMP_DIR=$(mktemp -d)

  curl -sL "${DOWNLOAD_URL}" -o "${TEMP_DIR}/${FILE}"
  echo "Extracting ${FILE} to ${TEMP_DIR}..."
  tar -xzf "${TEMP_DIR}/${FILE}" -C "${TEMP_DIR}"

  echo "Installing mev-commit to ${BINARY_PATH}..."
  sudo mv "${TEMP_DIR}/mev-commit" "${BINARY_PATH}"
  sudo chmod +x "${BINARY_PATH}"

  rm -rf "${TEMP_DIR}"
  echo "mev-commit downloaded and installed to ${BINARY_PATH}"
else
  echo "Using existing mev-commit binary found at ${BINARY_PATH}"
fi

###############################################################################
# 4) Print usage/info
###############################################################################
echo "**********************************************************************"
echo "  Starting up the mev-commit Bidder Node (v0.8.0)                     "
echo "**********************************************************************"
echo ""
echo "Configuration variables (current defaults):"
echo "  PRIVATE_KEY_BIDDER (required)    - your Ethereum private key"
echo "  DOMAIN: ${DOMAIN}"
echo "  AUTO_DEPOSIT_VALUE: ${AUTO_DEPOSIT_VALUE} (Wei)"
echo "  ENVIRONMENT: ${ENVIRONMENT}"
echo "  MEV_COMMIT_VERSION: ${MEV_COMMIT_VERSION}"
echo "  BINARY_PATH: ${BINARY_PATH}"
echo "  RPC_URL: ${RPC_URL}"
echo ""
echo "You can set these in a .env file or pass CLI args. Example usage:"
echo "  ./entrypoint.sh --private-key <HEXKEY> --auto-deposit 1000000000000000000"
echo ""

###############################################################################
# 5) Parse CLI arguments
###############################################################################
while [[ $# -gt 0 ]]; do
  case "$1" in
    --domain)
      DOMAIN="$2"
      shift 2
      ;;
    --private-key)
      PRIVATE_KEY_BIDDER="$2"
      shift 2
      ;;
    --auto-deposit)
      AUTO_DEPOSIT_VALUE="$2"
      shift 2
      ;;
    --binary-path)
      BINARY_PATH="$2"
      shift 2
      ;;
    --environment)
      ENVIRONMENT="$2"
      shift 2
      ;;
    --mev-commit-version)
      MEV_COMMIT_VERSION="$2"
      shift 2
      ;;
    --rpc-url)
      RPC_URL="$2"
      shift 2
      ;;
    --log-fmt)
      LOG_FMT="$2"
      shift 2
      ;;
    --log-level)
      LOG_LEVEL="$2"
      shift 2
      ;;
    *)
      echo "Unknown parameter: $1"
      exit 1
      ;;
  esac
done

###############################################################################
# 6) Ensure private key is set (prompt only if missing)
###############################################################################
if [ -z "${PRIVATE_KEY_BIDDER}" ]; then
  echo "No PRIVATE_KEY_BIDDER environment variable found."
  read -r -s -p "Enter your private key (hex, no 0x): " PRIVATE_KEY_BIDDER
  echo ""
fi

if [ -z "${PRIVATE_KEY_BIDDER}" ]; then
  echo "Error: No private key provided!"
  exit 1
fi

###############################################################################
# 7) Decide on auto-deposit (skip prompt if AUTO_DEPOSIT_VALUE is already set)
###############################################################################
# If user didn't override AUTO_DEPOSIT_VALUE, ask if they want the default
if [ "${AUTO_DEPOSIT_VALUE}" = "300000000000000000" ]; then
  # It's still the default. Confirm if user wants to override
  echo "Current auto-deposit: ${AUTO_DEPOSIT_VALUE} (default 0.3 ETH)."
  read -r -p "Use the default auto-deposit value? (y/n): " USE_DEFAULT_DEPOSIT
  if [[ ! "${USE_DEFAULT_DEPOSIT,,}" =~ ^(y|yes)$ ]]; then
    read -r -p "Enter custom auto-deposit value (in Wei): " AUTO_DEPOSIT_VALUE
  fi
else
  # If the user specified a custom value in ENV or CLI, skip the prompt
  echo "Using auto-deposit value from environment: ${AUTO_DEPOSIT_VALUE}"
fi

# For a bidder node, we enable auto-deposit by default
AUTO_DEPOSIT_ENABLED="true"

###############################################################################
# 8) Fetch contract addresses from ${CONTRACTS_URL}
###############################################################################
BOOTNODE="/dnsaddr/bootnode.${DOMAIN}"
CONTRACTS_URL="https://contracts.${DOMAIN}"

contracts_json=$(curl -sL "${CONTRACTS_URL}")
if ! echo "${contracts_json}" | jq . > /dev/null 2>&1; then
  echo "Failed to fetch contracts from ${CONTRACTS_URL}"
  exit 1
fi

BIDDER_REGISTRY_ADDR=$(echo "${contracts_json}" | jq -r '.BidderRegistry')
PROVIDER_REGISTRY_ADDR=$(echo "${contracts_json}" | jq -r '.ProviderRegistry')
BLOCK_TRACKER_ADDR=$(echo "${contracts_json}" | jq -r '.BlockTracker')
PRECONF_ADDR=$(echo "${contracts_json}" | jq -r '.PreconfManager')

###############################################################################
# 9) Build CLI flags for mev-commit 0.8.0
###############################################################################
FLAGS=(
  --peer-type "bidder"

  # Settlement RPC (WebSocket)
  --settlement-ws-rpc-endpoint "${RPC_URL}"

  # Logging
  --log-fmt "${LOG_FMT}"
  --log-level "${LOG_LEVEL}"

  # Bootnodes
  --bootnodes "${BOOTNODE}"

  # Key file is read from an in-memory FD
  --priv-key-file "${PRIV_KEY_FD}"

  # Bidder-specific
  --bidder-bid-timeout "15s"

  # Contracts
  --bidder-registry-contract "${BIDDER_REGISTRY_ADDR}"
  --provider-registry-contract "${PROVIDER_REGISTRY_ADDR}"
  --block-tracker-contract "${BLOCK_TRACKER_ADDR}"
  --preconf-contract "${PRECONF_ADDR}"

  # Auto-deposit
  --autodeposit-enabled="${AUTO_DEPOSIT_ENABLED}"
  --autodeposit-amount "${AUTO_DEPOSIT_VALUE}"
)

###############################################################################
# 10) Start mev-commit without writing key to disk
###############################################################################
echo ""
echo "Starting mev-commit with the following flags:"
for f in "${FLAGS[@]}"; do
  echo "  $f"
done
echo ""

# We open a file descriptor (FD #3) containing the private key in memory.
# mev-commit reads that FD as if it were a file, but nothing is written to disk.
exec 3<<< "${PRIVATE_KEY_BIDDER}"

exec "${BINARY_PATH}" "${FLAGS[@]}"
