# Kafka Webhook Bridge Service

This service acts as a bridge between external webhook providers and Kafka. It receives webhooks via HTTP and forwards them to Kafka topics.

## Features

- Receives webhooks via HTTP with Basic Authentication
- Forwards webhooks to Kafka topics
- Runs both locally and in AWS
- Supports multiple environments (test, staging, production)
- Handles message persistence and retry logic
- Provides monitoring and logging

## Local Development

### Local Development Prerequisites

- Docker and Docker Compose
- Node.js 18+
- AWS CLI (for deployment)
- 1Password CLI (for secret management)

### Local Environment Variables

Create a `.env` file in the root directory with the following variables:

```env
NODE_ENV=development
KAFKA_BROKERS=kafka:29092
KAFKA_USERNAME=kafka
KAFKA_PASSWORD=kafka
KAFKA_CLIENT_ID=kafka-webhook-bridge
KAFKA_SSL=false
PORT=3000
WEBHOOK_USERNAME=webhook
WEBHOOK_PASSWORD=webhook
```

### Running Locally

1. Start the local development environment:

   ```bash
   docker-compose up -d
   ```

2. The service will be available at `http://localhost:3000`

3. To stop the service:

   ```bash
   docker-compose down
   ```

## AWS Deployment

### AWS Deployment Prerequisites

- AWS CLI configured with appropriate credentials
- Access to AWS ECR, ECS, and Route53 services
- 1Password CLI configured with access to the Environments vault

### Environment Setup

1. Generate environment variables from 1Password:

   ```bash
   aws/get_env_vars.sh > .envrc
   direnv allow
   ```

   This will set up the following environment variables:
   - `KAFKA_USERNAME`
   - `KAFKA_PASSWORD`
   - `WEBHOOK_USERNAME`
   - `WEBHOOK_PASSWORD`
   - `HOSTED_ZONE_ID`

### Deployment

1. Deploy the stack:

   ```bash
   # Deploy with default image tag
   aws/deploy.sh webhook-bridge

   # Deploy with specific image tag
   aws/deploy.sh webhook-bridge v1.2.3
   ```

2. Update the stack:

   ```bash
   # Update with current image tag
   aws/update.sh webhook-bridge

   # Update with specific image tag
   aws/update.sh webhook-bridge v1.2.3
   ```

## Architecture

### Local Development Architecture

- Uses Docker Compose to run Kafka, Zookeeper, and the service
- Kafka runs in a single-node configuration
- No SSL/TLS encryption for local development

### AWS Production Architecture

- Runs on AWS ECS Fargate
- Uses self-contained Kafka cluster on ECS
- Implements SSL/TLS encryption with ACM certificates
- Uses EFS for persistent storage
- Includes monitoring and logging via CloudWatch
- Uses Route53 for DNS management

## Webhook Endpoints

### Health Check

- `GET /health` - Health check endpoint

### Webhook Endpoint

- `POST /webhook` - Main webhook endpoint (requires Basic Authentication)

## Monitoring and Logging

- Application logs are sent to CloudWatch Logs
- Health check endpoint at `/health`
- ECS service metrics available in CloudWatch

## Security

- Webhook endpoints use HTTP Basic Authentication
- Kafka connections use SASL/SCRAM authentication
- TLS encryption for all external communications
- EFS encryption for data at rest

## Troubleshooting

### Common Issues

1. Connection Issues

   - Check Kafka broker connectivity
   - Verify SSL/TLS configuration
   - Check security group settings

2. Authentication Failures

   - Verify webhook credentials
   - Check Kafka credentials
   - Ensure proper IAM roles are configured

3. Message Processing Failures
   - Check application logs in CloudWatch
   - Verify Kafka topic configuration
   - Check message format and validation

## Contributing

1. Create a feature branch
2. Make your changes
3. Run tests and linting
4. Submit a pull request

## License

Proprietary - All rights reserved
