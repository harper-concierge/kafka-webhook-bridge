#!/bin/bash

set -euo pipefail

# Function to print usage
usage() {
    echo "Usage: $0 <environment>"
    echo "  environment: 'local' or any environment name (test, staging, production)"
    echo
    echo "Required environment variables:"
    echo "  KAFKA_USERNAME - Username for Kafka authentication"
    echo "  KAFKA_PASSWORD - Password for Kafka authentication"
    echo "  HOSTED_ZONE_ID - AWS Route53 Hosted Zone ID (for non-local environments)"
    echo
    echo "For local environment, if KAFKA_USERNAME and KAFKA_PASSWORD are not set, defaults will be used"
    exit 1
}

# Check if environment argument is provided
if [[ $# -ne 1 ]]; then
    usage
fi

ENVIRONMENT="$1"

# Set environment-specific variables
if [[ "$ENVIRONMENT" == "local" ]]; then
    KAFKA_BROKERS="localhost:9092"
    # Check if env vars are set, otherwise use defaults
    KAFKA_USERNAME="${KAFKA_USERNAME:-kafka}"
    KAFKA_PASSWORD="${KAFKA_PASSWORD:-kafka}"
else
    # For deployed environments, use the domain from the stack
    if [[ -z "${HOSTED_ZONE_ID:-}" ]]; then
        echo "Error: HOSTED_ZONE_ID environment variable is required for non-local environments"
        exit 1
    fi
    DOMAIN_NAME=$(aws route53 get-hosted-zone --id "$HOSTED_ZONE_ID" --query 'HostedZone.Name' --output text | sed 's/\.$//')
    KAFKA_BROKERS="${ENVIRONMENT}-kafka-api-bridge.${DOMAIN_NAME}:29092"
fi

# Function to create a topic
create_topic() {
    local topic_name="$1"
    local partitions="$2"
    local replication_factor="$3"

    echo "Creating topic: $topic_name"
    if [[ "$ENVIRONMENT" == "local" ]]; then
        # Ignore errors if topic already exists
        docker-compose exec kafka kafka-topics \
            --create \
            --topic "$topic_name" \
            --bootstrap-server kafka:9092 \
            --partitions "$partitions" \
            --replication-factor "$replication_factor" \
            --config cleanup.policy=delete \
            --config retention.ms=604800000 || true
    else
        # For deployed environments, use the REST proxy
        curl -X POST "https://${ENVIRONMENT}-kafka-api-bridge.${DOMAIN_NAME}/v3/clusters/${CLUSTER_ID}/topics" \
            -u "$KAFKA_USERNAME:$KAFKA_PASSWORD" \
            -H "Content-Type: application/json" \
            -d "{
                \"topic_name\": \"$topic_name\",
                \"partitions_count\": $partitions,
                \"replication_factor\": $replication_factor,
                \"configs\": [
                    {
                        \"name\": \"cleanup.policy\",
                        \"value\": \"delete\"
                    },
                    {
                        \"name\": \"retention.ms\",
                        \"value\": \"604800000\"
                    }
                ]
            }" || true
    fi
    echo
}

# Create topics
echo "Creating topics for $ENVIRONMENT environment..."
create_topic "shopify" 3 1
create_topic "centra" 3 1
create_topic "bigcommerce" 3 1
create_topic "salesforce" 3 1
create_topic "magento" 3 1

echo "Topics created successfully!" 