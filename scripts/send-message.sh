#!/bin/bash
# Script to test the webhook service with various topics and HTTP methods

# Configuration
HOST=${WEBHOOK_HOST:-"localhost:3000"}
USERNAME=${WEBHOOK_USERNAME:-"admin"}
PASSWORD=${WEBHOOK_PASSWORD:-"admin-secret"}
PROTOCOL="https"
AUTH_HEADER="Authorization: Basic $(echo -n "$USERNAME:$PASSWORD" | base64)"

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Test function
send_request() {
  local method=$1
  local topic=$2
  local path=$3
  local payload=$4
  local url="${PROTOCOL}://$HOST/webhooks/$topic/$path"

  echo -e "${BLUE}Sending $method request to topic '$topic' with path '$path'${NC}"

  if [ "$method" == "GET" ] || [ "$method" == "DELETE" ]; then
    # GET and DELETE requests don't have a body
    response=$(curl -s -X "$method" \
      -H "$AUTH_HEADER" \
      -H "Content-Type: application/json" \
      "$url")
  else
    # POST, PUT, PATCH with payload
    response=$(curl -s -X "$method" \
      -H "$AUTH_HEADER" \
      -H "Content-Type: application/json" \
      -d "$payload" \
      "$url")
  fi

  # Check if successful
  if echo "$response" | grep -q '"status":"ok"'; then
    echo -e "${GREEN}Success!${NC} Message sent to Kafka"
    echo -e "${YELLOW}Response:${NC} $response"
  else
    echo -e "${RED}Error!${NC} Failed to send message"
    echo -e "${YELLOW}Response:${NC} $response"
  fi
  echo ""
}

# Main test sequence
echo -e "${BLUE}=== Testing Webhook Service at ${PROTOCOL}://$HOST ===${NC}"

# Test various topics and methods
echo -e "${BLUE}Testing with different topics and HTTP methods...${NC}"

# GitHub webhook simulation
send_request "POST" "harper-concierge-dev" "return/create" '{
  "event": "push",
  "ref": "refs/heads/main",
  "repository": {
    "name": "test-repo",
    "full_name": "user/test-repo"
  },
  "commits": [
    {
      "id": "abc123",
      "message": "Test commit"
    }
  ]
}'

# Stripe webhook simulation
send_request "POST" "harper-centra-dev" "refund/create" '{
  "event": "charge.succeeded",
  "data": {
    "object": {
      "id": "ch_123456",
      "amount": 1000,
      "currency": "usd"
    }
  }
}'

# Test with GET method
send_request "GET" "harper-magento-dev" "fulfilment/create" ''

echo -e "${BLUE}=== Testing Complete ===${NC}"