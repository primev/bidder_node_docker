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

## Customization
Environment Variables
You can customize the following environment variables in the .env file or Docker Compose:

- PRIVATE_KEY_BIDDER: Your private key for authenticating the node with the testnet.
- DOMAIN: The MEV-Commit testnet domain, default is testnet.mev-commit.xyz.

## Modifying the Entry Point
The container uses the entrypoint.sh script to start the service. If you need to modify the startup sequence, you can edit this script and rebuild the container. Some reasons to modify the script include:
* build the bidder node from a previous mev-commit version
* change the autodeposit minimum deposit amount (1 ETH)

# Networking with Other Repositories
This Docker container is designed to work together with other services (e.g., bidding scripts or Geth containers) by using a shared Docker network. This allows multiple containers to communicate with each other seamlessly.

### Why a Docker Network Is Needed
To allow the mev-commit-bidder service to interact with other containers (like a searcher bot) that are defined in different repositories, we use a Docker network. This network allows services to discover and communicate with each other via container names instead of hardcoded IP addresses.

### Creating the Network
Before running the containers, ensure that the shared network is created. This only needs to be done once:

```bash
docker network create app-network
```

The app-network allows the bidder node and other services (e.g., a bid sender) to communicate over the same network.

### Using the Network with Other Repositories
If you have other repositories with Docker services that need to communicate with this bidder node, make sure they also reference the same app-network. Here's an example of how to include this network in another repository’s docker-compose.yml:

```yaml
version: '3'
services:
  bid-sender:
    networks:
      - app-network
    environment:
      - RPC_ENDPOINT=http://mev-commit-bidder:13524
networks:
  app-network:
    external: true
```
This ensures that the containers across different repositories can communicate with each other using container names, like mev-commit-bidder, for service discovery.


# Troubleshooting
Service not starting: Check the logs using:

```bash
docker-compose logs mev-commit-bidder
```

## Logs
To monitor the logs of the running bidder service:

```bash
docker-compose logs -f mev-commit-bidder
```