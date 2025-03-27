# Kafka Webhook Bridge

A service that bridges webhook requests to Kafka topics, supporting both local development and AWS deployment.

## Architecture Overview

The system consists of two main components:
1. Kafka (message broker with KRaft mode)
2. Webhook Proxy (receives webhooks and forwards to Kafka)

### Security Model

- **External Webhook Access**: HTTPS terminated at the load balancer (AWS) or nginx-proxy (local)
- **Internal Communication**: 
  - Local: Plain text between services
  - AWS: SSL/TLS between services, terminated at the load balancer
- **Authentication**:
  - Webhook endpoints: Basic Auth
  - Kafka: SASL/PLAIN authentication for external client connections only

#### Security Architecture

1. **External Access (Client → Kafka)**:
   - SSL/TLS terminated at the load balancer (ALB in AWS) or nginx-proxy (local)
   - SASL/PLAIN authentication for client connections
   - This provides both encryption and authentication for external clients

2. **Internal Communication (Kafka Controller)**:
   - Plaintext communication is secure because:
     - All services run in private subnets (AWS) or Docker network (local)
     - Network access is controlled by security groups (AWS) or Docker network (local)
     - No direct internet access to these services
     - Communication is internal to the VPC/network

3. **Security Layers**:
   - Network level: Private subnets + Security groups (AWS) or Docker network (local)
   - Transport level: SSL/TLS at load balancer
   - Application level: SASL/PLAIN for client authentication

This security model follows production best practices where:
- The load balancer handles SSL/TLS termination
- Internal services communicate over a trusted network
- Authentication is handled at the application level
- Network security is handled at the infrastructure level

## Local Development Setup

### Prerequisites

- Docker and Docker Compose
- Node.js 20+
- Make (optional, for using Makefile commands)

### Nginx Proxy Configuration

The local setup uses a custom nginx-proxy configuration with the following key components:

1. **Container Name**: `nginx-proxy-kafka`
   - This specific name is required for proper SSL certificate management
   - The acme-companion service is configured to look for this container name

2. **Required Labels**:
   ```yaml
   labels:
     - "com.github.nginx-proxy.nginx=true"
   ```
   This label is required for the acme-companion to identify the nginx-proxy container.

3. **Volume Mounts**:
   - `/var/run/docker.sock`: For Docker API access
   - `./nginx/certs`: For SSL certificates
   - `./nginx/vhost.d`: For virtual host configurations
   - `./nginx/html`: For static content
   - `./nginx/conf.d`: For custom nginx configurations

4. **Ports**:
   - `80`: HTTP traffic
   - `443`: HTTPS traffic

5. **Environment Variables**:
   - `NGINX_PROXY_CONTAINER=nginx-proxy-kafka`: Required for acme-companion to identify the proxy container
   - `DEFAULT_EMAIL`: Your email for SSL certificate notifications

### Local Development Architecture

```
[Client] -> [Nginx Proxy] -> [Webhook Proxy] -> [Kafka (KRaft)]
```

The local setup uses nginx-proxy for SSL termination and routing, with services running in Docker Compose.

### Initial Setup

1. Clone the repository
2. Configure your local environment variables using `.envrc`:
   ```bash
   export KAFKA_BROKER_USERNAME=your_kafka_username
   export KAFKA_BROKER_PASSWORD=your_kafka_password
   ```
   Note: These variables are used for local development only. In AWS, these will be managed through CloudFormation parameters.

3. Set up nginx directories and permissions:
   ```bash
   chmod +x scripts/setup-nginx.sh
   ./scripts/setup-nginx.sh
   ```

4. Ensure your `/etc/hosts` file has the following entry:
   ```
   127.0.0.1 webhook.harperconcierge.dev
   ```

### Running Locally

1. Start the services:
   ```bash
   docker-compose up -d
   ```

2. The services will be available at:
   - Webhook Proxy: https://webhook.harperconcierge.dev
   - Kafka: localhost:9094

### Common Issues and Solutions

1. **Nginx Proxy ACME Companion Issues**
   - Error: "can't get nginx-proxy container ID"
   - Solution: The docker-compose.yml now includes:
     - Label `com.github.nginx-proxy.nginx=true` on the nginx-proxy service
     - Environment variable `NGINX_PROXY_CONTAINER=nginx-proxy-kafka` on the acme-companion service

2. **SSL Certificate Issues**
   - The nginx-proxy-acme service will automatically request SSL certificates
   - Make sure your domain (webhook.harperconcierge.dev) is properly configured in /etc/hosts
   - Check nginx/certs directory permissions if certificate generation fails

4. **Container Health Checks**
   - Services are configured with health checks to ensure proper startup order
   - If a service fails to start, check the logs:
     ```bash
     docker-compose logs <service-name>
     ```

### Development Workflow

1. Make changes to the webhook proxy code
2. Rebuild and restart the webhook service:
   ```bash
   docker-compose build webhook
   docker-compose up -d webhook
   ```

3. View logs:
   ```bash
   docker-compose logs -f webhook
   ```

## AWS Deployment

### Architecture

```
[Client] -> [ALB] -> [ECS Service] -> [Webhook Proxy] -> [Kafka]
```

All services run in a single ECS service with the following configuration:
- Fargate launch type
- No Auto-scaling. Single task
- Application Load Balancer for SSL termination
- VPC endpoints for ECR and CloudWatch Logs
- Security groups for internal communication
- Kafka & zookeper have access to a persistent storage

### Deployment Process

1. Build and push Docker images to ECR:
   ```bash
   ./scripts/release.sh
   ```

2. Deploy the CloudFormation stack:
   ```bash
   ./aws/deploy.sh production v1.0.13
   ```

3. Update the stack (when needed):
   ```bash
   ./aws/update.sh production [v1.0.13] #optional
   ```

### Security Implementation

1. **SSL/TLS Certificates**:
   - Automatically generated using AWS Certificate Manager
   - Managed through CloudFormation
   - No certificates committed to the repository

2. **Authentication**:
   - Webhook credentials managed through environment Variables and passed through as parameters
   - Kafka credentials managed through environment Variables and passed through as parameters
   - Zookeeper credentials internally hard configured

3. **Network Security**:
   - All services run in private subnets
   - VPC endpoints for AWS services
   - Security groups for service-to-service communication

## Configuration

### Environment Variables

Key environment variables for local development (configured via `.envrc`):
- `KAFKA_BROKER_USERNAME`: Kafka client username
- `KAFKA_BROKER_PASSWORD`: Kafka client password
- `KAFKA_CONTAINER_IMAGE`: Override default Kafka image
- `KAFKA_HOSTED_ZONE_ID`: AWS Route 53 hosted zone ID for DNS management
- `ZOOKEEPER_CONTAINER_IMAGE`: Override default Zookeeper image

Note: These environment variables are used for local development only. In AWS, these values will be managed through CloudFormation parameters and AWS Systems Manager Parameter Store.

### Docker Images

- Kafka: `bitnami/kafka:3.6`
- Webhook Proxy: Custom image built from `Dockerfile`
- Nginx Proxy: `nginxproxy/nginx-proxy:latest`
- ACME Companion: `nginxproxy/acme-companion:latest`

### Environment Variable Naming Conventions

- **Bitnami Images**: Use `KAFKA_CFG_*` prefix for Kafka configurations (e.g., `KAFKA_CFG_LISTENERS`, `KAFKA_CFG_ADVERTISED_LISTENERS`)
- **Webhook Service**: Uses standard environment variable names (e.g., `KAFKA_*`, `WEBHOOK_*`)
- **Nginx Proxy**: Uses standard environment variable names (e.g., `NGINX_*`)

### Service Configuration Details

#### Kafka Configuration (KRaft Mode)
- **Platform**: linux/arm64 (for M1/M2 Macs)
- **Ports**: 
  - 9092: Internal communication (inter-broker)
  - 9093: Controller communication
  - 9094: External access (client)
- **Authentication**: SASL/PLAIN for client connections only
- **Health Check**: Uses kafka-topics.sh to verify broker availability
- **Volume**: Persistent storage for data
- **Key Environment Variables**:
  ```env
  # KRaft Configuration
  KAFKA_ENABLE_KRAFT=yes
  KAFKA_CFG_PROCESS_ROLES=broker,controller
  KAFKA_CFG_NODE_ID=1
  KAFKA_CFG_CONTROLLER_QUORUM_VOTERS=1@127.0.0.1:9093

  # Listener configuration
  KAFKA_CFG_LISTENERS=BROKER://:9092,CONTROLLER://:9093,EXTERNAL://0.0.0.0:9094
  KAFKA_CFG_ADVERTISED_LISTENERS=BROKER://localhost:9092,EXTERNAL://localhost:9094
  KAFKA_CFG_LISTENER_SECURITY_PROTOCOL_MAP=BROKER:SASL_PLAINTEXT,CONTROLLER:PLAINTEXT,EXTERNAL:SASL_PLAINTEXT
  KAFKA_CFG_CONTROLLER_LISTENER_NAMES=CONTROLLER
  KAFKA_CFG_INTER_BROKER_LISTENER_NAME=BROKER

  # SASL Configuration
  KAFKA_CFG_SASL_ENABLED=true
  KAFKA_CFG_SASL_MECHANISM=PLAIN
  KAFKA_CFG_SASL_ENABLED_MECHANISMS=PLAIN
  KAFKA_CFG_SASL_MECHANISM_INTER_BROKER_PROTOCOL=PLAIN
  KAFKA_CFG_SASL_MECHANISM_CONTROLLER_PROTOCOL=PLAIN
  KAFKA_CFG_LISTENER_NAME_BROKER_PLAIN_SASL_JAAS_CONFIG=org.apache.kafka.common.security.plain.PlainLoginModule required username="${KAFKA_BROKER_USERNAME}" password="${KAFKA_BROKER_PASSWORD}" user_${KAFKA_BROKER_USERNAME}="${KAFKA_BROKER_PASSWORD}";
  KAFKA_CFG_LISTENER_NAME_EXTERNAL_PLAIN_SASL_JAAS_CONFIG=org.apache.kafka.common.security.plain.PlainLoginModule required username="${KAFKA_BROKER_USERNAME}" password="${KAFKA_BROKER_PASSWORD}" user_${KAFKA_BROKER_USERNAME}="${KAFKA_BROKER_PASSWORD}";

  # Broker configuration
  KAFKA_CFG_NUM_PARTITIONS=3
  KAFKA_CFG_DEFAULT_REPLICATION_FACTOR=1
  KAFKA_CFG_OFFSETS_TOPIC_REPLICATION_FACTOR=1
  KAFKA_CFG_TRANSACTION_STATE_LOG_REPLICATION_FACTOR=1
  KAFKA_CFG_TRANSACTION_STATE_LOG_MIN_ISR=1
  ```

#### Webhook Service Configuration
- **Port**: 3000 (internal only, exposed to nginx-proxy)
- **Health Check**: HTTP endpoint at /health
- **Key Environment Variables**:
  ```env
  NODE_ENV=development
  KAFKA_BROKERS=kafka:9092
  KAFKA_CLIENT_ID=kafka-webhook-bridge
  KAFKA_SSL=false
  KAFKA_SASL=true
  KAFKA_SASL_MECHANISM=PLAIN
  KAFKA_SASL_USERNAME=${KAFKA_USERNAME}
  KAFKA_SASL_PASSWORD=${KAFKA_PASSWORD}
  PORT=3000
  WEBHOOK_USERNAME=${WEBHOOK_USERNAME:-webhook}
  WEBHOOK_PASSWORD=${WEBHOOK_PASSWORD:-webhook}
  ```

### Service Dependencies and Health Checks
- Kafka must be healthy before Webhook service starts
- Health checks are configured for all services to ensure proper startup order
- Services use the `webhook-network` bridge network for internal communication

### Volume Management
- Kafka data is persisted in `kafka_data` volume
- Nginx certificates and configurations are stored in local `./nginx` directory

## Monitoring and Logging

- CloudWatch Logs for all container logs
- CloudWatch Metrics for service health
- Container Insights for detailed monitoring
- Health checks configured for all services

## Development Workflow

1. Local development using Docker Compose
2. Testing with local Kafka and Zookeeper
3. CI/CD pipeline for automated testing
4. Deployment to AWS using CloudFormation

## Maintenance

### Updating Dependencies

1. Update package.json
2. Update Dockerfile if needed
3. Update CloudFormation template if AWS services need updating
4. Deploy changes using the update script

### Scaling

- ECS service auto-scales based on CPU/Memory utilization
- Kafka partitions can be increased through CloudFormation parameters
- Zookeeper ensemble can be expanded if needed

## Troubleshooting

### Common Issues

1. **Connection Issues**:
   - Check security groups
   - Verify VPC endpoints
   - Check service health in ECS

2. **Authentication Failures**:
   - Verify credentials in AWS Secrets Manager
   - Check environment variables
   - Review CloudWatch logs

3. **Performance Issues**:
   - Monitor CloudWatch metrics
   - Check Kafka partition configuration
   - Review container resource allocation

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Submit a pull request

## License

See LICENSE file for details.
