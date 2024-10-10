# MEV-Commit Bidder Docker Setup
This repository contains the Docker setup for running a MEV-Commit bidder node service in one container. The bidder node connects to the mev-commmit testnet and lets a user submit bids on the network.

# Prerequisites
- Docker and Docker Compose installed on your machine
- A funded mev-commit address and valid private key - [faucet](https://faucet.testnet.mev-commit.xyz/) to receive funds.

# Setup Instructions
1. Clone the repository
2. Prepare Environment Variables
Create a .env file in the root of the repository and define the PRIVATE_KEY_BIDDER variable

3. Build and Run the Docker Containers
Run the following command to build the Docker image and start the bidder node service:

```bash 
docker-compose up --build
```

- Build the Docker image based on Ubuntu 20.04
- Install necessary dependencies (curl, jq, etc.)
- Download and install the latest mev-commit binary from the official repository

## Port Configuration
The mev-commit-bidder service exposes the following port:

## Customization
Environment Variables
You can customize the following environment variables in the .env file or Docker Compose:

- PRIVATE_KEY_BIDDER: Your private key for authenticating the node with the testnet.
- DOMAIN: The MEV-Commit testnet domain, default is testnet.mev-commit.xyz.

## Modifying the Entry Point
The container uses the entrypoint.sh script to start the service. If you need to modify the startup sequence, you can edit this script and rebuild the container.

# Additional Notes
The mev-commit binary is downloaded during the build process from the official GitHub repository.
The containers are configured to automatically restart on failure using Docker Compose.

## Troubleshooting
Service not starting: Check the logs using:

```bash
docker-compose logs mev-commit-bidder
```

### Logs
To monitor the logs of the running bidder service:

```bash
docker-compose logs -f mev-commit-bidder
```