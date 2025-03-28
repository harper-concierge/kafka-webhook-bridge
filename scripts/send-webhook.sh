#!/bin/bash

set -euo pipefail

# Default values
ENV=${ENV:-local}
WEBHOOK_URL=${WEBHOOK_URL:-https://webhooks.harperconcierge.dev:443/webhook}
WEBHOOK_USERNAME=${WEBHOOK_USERNAME:-webhook}
WEBHOOK_PASSWORD=${WEBHOOK_PASSWORD:-webhook}

# Function to display usage
usage() {
    echo "Usage: $0 [options]"
    echo "Options:"
    echo "  -e, --env <environment>    Environment (local|production) [default: local]"
    echo "  -u, --url <url>           Webhook URL [default: https://webhooks.harperconcierge.dev/webhook]"
    echo "  -n, --username <username>  Basic auth username [default: webhook]"
    echo "  -p, --password <password>  Basic auth password [default: webhook]"
    echo "  -h, --help                Display this help message"
    exit 1
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -e|--env)
            ENV="$2"
            shift 2
            ;;
        -u|--url)
            WEBHOOK_URL="$2"
            shift 2
            ;;
        -n|--username)
            WEBHOOK_USERNAME="$2"
            shift 2
            ;;
        -p|--password)
            WEBHOOK_PASSWORD="$2"
            shift 2
            ;;
        -h|--help)
            usage
            ;;
        *)
            echo "Unknown option: $1"
            usage
            ;;
    esac
done

# Set production URL if environment is production
if [ "$ENV" = "production" ]; then
    WEBHOOK_URL="https://${DOMAIN_NAME}/webhook"
fi

# Send the webhook
echo "Sending Shopify webhook to $WEBHOOK_URL..."
curl -k -X POST "$WEBHOOK_URL" \
    -H "Content-Type: application/json" \
    -H "X-Shopify-Topic: orders/create" \
    -H "X-Shopify-Shop-Domain: your-store.myshopify.com" \
    -H "X-Shopify-Hmac-SHA256: example_hmac_hash" \
    -H "X-Shopify-API-Version: 2024-01" \
    -u "${WEBHOOK_USERNAME}:${WEBHOOK_PASSWORD}" \
    -d '{
        "event": "orders/create",
        "data": {
            "id": 123456789,
            "email": "customer@example.com",
            "total_price": "99.99",
            "currency": "USD",
            "created_at": "2024-03-27T18:45:00Z",
            "line_items": [
                {
                    "id": 987654321,
                    "title": "Test Product",
                    "quantity": 1,
                    "price": "99.99"
                }
            ],
            "shipping_address": {
                "first_name": "John",
                "last_name": "Doe",
                "address1": "123 Main St",
                "city": "New York",
                "province": "NY",
                "zip": "10001",
                "country": "United States"
            }
        }
    }'

echo -e "\nWebhook sent successfully!"