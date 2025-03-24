#!/bin/bash

set -euo pipefail

echo "Stopping all containers..."
docker-compose down

echo "Removing Kafka and Zookeeper volumes..."
docker volume rm kafka-webhook-bridge_kafka_data kafka-webhook-bridge_zookeeper_data || true

echo "Cleanup complete. You can now run 'docker-compose up' to start fresh." 