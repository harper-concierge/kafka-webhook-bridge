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

# Check prerequisites
check_command docker
check_command docker-compose
check_command nc

# Start the services
echo "Starting services..."
docker-compose up -d

# Wait for services to be ready
wait_for_service localhost 9292 "Kafka"
wait_for_service localhost 3000 "Webhook Service"

# Wait for Kafka to be fully ready
echo "Waiting for Kafka to be fully ready..."
sleep 10

# Create a test topic (ignore error if it exists)
echo "Creating test topic..."
docker-compose exec kafka kafka-topics --create \
  --topic webhook-events \
  --bootstrap-server kafka:9092 \
  --replication-factor 1 \
  --partitions 1 || true

# Start a Kafka consumer in the background
echo "Starting Kafka consumer..."
docker-compose exec -T kafka kafka-console-consumer \
  --bootstrap-server kafka:9092 \
  --topic webhook-events \
  --from-beginning &

# Store the consumer PID
CONSUMER_PID=$!

# Wait a moment for the consumer to start
sleep 2

# Send a test webhook
echo "Sending test webhook..."
curl -X POST http://localhost:3000/webhook \
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