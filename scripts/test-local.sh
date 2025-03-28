#!/bin/bash

set -e

# Function to wait for a service to be ready
wait_for_service() {
    local host=$1
    local port=$2
    local service=$3
    local max_attempts=30
    local attempt=1

    echo "Waiting for $service to be ready..."
    while ! nc -z $host $port; do
        if [ $attempt -eq $max_attempts ]; then
            echo "Error: $service failed to start after $max_attempts attempts"
            exit 1
        fi
        echo "Attempt $attempt/$max_attempts: $service not ready yet..."
        sleep 2
        attempt=$((attempt + 1))
    done
    echo "$service is ready!"
}

# Function to check if a command exists
check_command() {
    if ! command -v $1 &> /dev/null; then
        echo "Error: $1 is required but not installed."
        exit 1
    fi
}

# Function to check if a service is healthy
check_service_health() {
    local service=$1
    local max_attempts=30
    local attempt=1

    echo "Checking $service health..."
    while ! docker-compose ps $service | grep -q "healthy"; do
        if [ $attempt -eq $max_attempts ]; then
            echo "Error: $service failed to become healthy after $max_attempts attempts"
            exit 1
        fi
        echo "Attempt $attempt/$max_attempts: $service not healthy yet..."
        sleep 2
        attempt=$((attempt + 1))
    done
    echo "$service is healthy!"
}

# Function to check if webhook is accessible through nginx
check_webhook_access() {
    local max_attempts=10
    local attempt=1

    echo "Checking webhook accessibility through nginx..."
    while ! curl -s -f -o /dev/null -w "%{http_code}" http://webhook.harperconcierge.dev/health | grep -q "200"; do
        if [ $attempt -eq $max_attempts ]; then
            echo "Error: Webhook not accessible through nginx after $max_attempts attempts"
            exit 1
        fi
        echo "Attempt $attempt/$max_attempts: Webhook not accessible yet..."
        sleep 2
        attempt=$((attempt + 1))
    done
    echo "Webhook is accessible through nginx!"
}

# Check prerequisites
check_command docker
check_command docker-compose
check_command nc

# Set up nginx directories if they don't exist
echo "Setting up nginx directories..."
./scripts/setup-nginx.sh

# Start the services
echo "Starting services..."
docker-compose up -d

# Wait for services to be ready
wait_for_service localhost 2181 "Zookeeper"
wait_for_service localhost 9092 "Kafka"
wait_for_service localhost 80 "Nginx Proxy"

# Check service health
check_service_health zookeeper
check_service_health kafka
check_service_health webhook

# Check webhook accessibility through nginx
check_webhook_access

# Wait for Kafka to be fully ready
echo "Waiting for Kafka to be fully ready..."
sleep 10

# Create a test topic (ignore error if it exists)
echo "Creating test topic..."
docker-compose exec kafka kafka-topics --create \
  --topic webhook-events \
  --bootstrap-server kafka:9092 \
  --replication-factor 1 \
  --partitions 1 \
  --command-config /opt/bitnami/kafka/config/kafka.properties || true

# Start a Kafka consumer in the background
echo "Starting Kafka consumer..."
docker-compose exec -T kafka kafka-console-consumer \
  --bootstrap-server kafka:9092 \
  --topic webhook-events \
  --from-beginning \
  --consumer.config /opt/bitnami/kafka/config/kafka.properties &

# Store the consumer PID
CONSUMER_PID=$!

# Wait a moment for the consumer to start
sleep 2

# Send a test webhook
echo "Sending test webhook..."
curl -X POST http://webhook.harperconcierge.dev/webhook \
  -H "Content-Type: application/json" \
  -u "${WEBHOOK_USERNAME:-webhook}:${WEBHOOK_PASSWORD:-webhook}" \
  -d '{
    "event": "test",
    "data": {
      "message": "Hello from test script!"
    }
  }'

# Wait a moment for the message to be processed
sleep 2

# Clean up
echo "Cleaning up..."
kill $CONSUMER_PID
docker-compose down

echo "Test complete!" 