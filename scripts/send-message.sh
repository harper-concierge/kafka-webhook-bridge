#!/bin/bash
# Script to test the webhook service with various e-commerce platform webhooks

# Configuration
HOST=${WEBHOOK_DOMAIN:-"localhost:3000"}
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
    echo -e "${GREEN}Success!${NC} Message sent to Kafka topic '$topic'"
    echo -e "${YELLOW}Response:${NC} $response"
  else
    echo -e "${RED}Error!${NC} Failed to send message"
    echo -e "${YELLOW}Response:${NC} $response"
  fi
  echo ""
}

# Main test sequence
echo -e "${BLUE}=== Testing E-commerce Webhook Service at ${PROTOCOL}://$HOST ===${NC}"

# Shopify Order Creation
echo -e "${BLUE}Testing Shopify Order Creation...${NC}"
send_request "POST" "shopify" "orders/create" '{
  "id": 123456789,
  "email": "customer@example.com",
  "created_at": "2024-03-20T10:00:00Z",
  "total_price": "99.99",
  "currency": "USD",
  "line_items": [
    {
      "title": "Product Name",
      "quantity": 1,
      "price": "99.99"
    }
  ]
}'

# Stripe Payment Success
echo -e "${BLUE}Testing Stripe Payment Success...${NC}"
send_request "POST" "stripe" "payment-events" '{
  "id": "evt_123456789",
  "type": "payment_intent.succeeded",
  "object": "event",
  "api_version": "2023-10-16",
  "created": 1710936000,
  "data": {
    "object": {
      "id": "pi_123456789",
      "amount": 9999,
      "currency": "usd",
      "customer": "cus_123456789",
      "status": "succeeded"
    }
  },
  "livemode": false,
  "pending_webhooks": 0,
  "request": null,
  "type": "payment_intent.succeeded"
}'

# Centra Fulfillment
echo -e "${BLUE}Testing Centra Fulfillment...${NC}"
send_request "POST" "centra" "fulfilment/partner123" '{
  "event": "fulfillment.created",
  "timestamp": "2024-03-20T10:00:00Z",
  "data": {
    "orderId": "ORD-123456789",
    "fulfillmentId": "FUL-123456789",
    "status": "created",
    "items": [
      {
        "orderItemId": "ITEM-123456789",
        "sku": "PROD-123456789",
        "quantity": 1,
        "warehouse": "MAIN-WAREHOUSE"
      }
    ],
    "shipping": {
      "carrier": "DHL",
      "trackingNumber": "1234567890",
      "trackingUrl": "https://www.dhl.com/tracking/1234567890"
    }
  }
}'

# Centra Refund
echo -e "${BLUE}Testing Centra Refund...${NC}"
send_request "POST" "centra" "refund/partner123" '{
  "event": "refund.created",
  "timestamp": "2024-03-20T10:00:00Z",
  "data": {
    "orderId": "ORD-123456789",
    "refundId": "REF-123456789",
    "status": "created",
    "amount": 100.00,
    "currency": "USD",
    "reason": "Customer request",
    "items": [
      {
        "orderItemId": "ITEM-123456789",
        "quantity": 1,
        "amount": 100.00
      }
    ]
  }
}'

# Centra Order Cancellation
echo -e "${BLUE}Testing Centra Order Cancellation...${NC}"
send_request "POST" "centra" "cancel-order/partner123" '{
  "event": "order.cancelled",
  "timestamp": "2024-03-20T10:00:00Z",
  "data": {
    "orderId": "ORD-123456789",
    "status": "cancelled",
    "reason": "Customer request",
    "cancelledAt": "2024-03-20T10:00:00Z"
  }
}'

# 17Track Tracking Update
echo -e "${BLUE}Testing 17Track Tracking Update...${NC}"
send_request "POST" "17track" "tracking-updated" '{
  "event": "tracking.updated",
  "timestamp": "2024-03-20T10:00:00Z",
  "data": {
    "trackingNumber": "DHL123456789",
    "status": "delivered",
    "location": "New York, USA",
    "timestamp": "2024-03-20T10:00:00Z",
    "details": "Package delivered to recipient"
  }
}'

# Rebound Return Request
echo -e "${BLUE}Testing Rebound Return Request...${NC}"
send_request "POST" "rebound" "return-request/partner123" '{
  "event": "return.requested",
  "timestamp": "2024-03-20T10:00:00Z",
  "data": {
    "returnId": "RET123",
    "orderId": "ORD123",
    "status": "pending",
    "items": [
      {
        "orderItemId": "ITEM123",
        "quantity": 1,
        "reason": "Wrong size"
      }
    ],
    "customer": {
      "name": "John Doe",
      "email": "john@example.com"
    }
  }
}'

# Rebound Return
echo -e "${BLUE}Testing Rebound Return...${NC}"
send_request "POST" "rebound" "return/partner123" '{
  "event": "return.created",
  "timestamp": "2024-03-20T10:00:00Z",
  "data": {
    "returnId": "RET123",
    "orderId": "ORD123",
    "status": "processing",
    "items": [
      {
        "orderItemId": "ITEM123",
        "quantity": 1,
        "condition": "unworn"
      }
    ],
    "shipping": {
      "carrier": "UPS",
      "trackingNumber": "UPS123456789"
    }
  }
}'

echo -e "${BLUE}=== Testing Complete ===${NC}"