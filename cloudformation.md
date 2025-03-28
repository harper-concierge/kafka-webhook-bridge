# AWS CloudFormation Deployment Strategy

## Overview

This document outlines the strategy for deploying the Kafka Webhook Bridge to AWS using CloudFormation, based on our working Docker Compose setup. The key focus is on maintaining the same security model and listener configuration while adapting it for AWS infrastructure.

## Important Notes
### AWS Resource Naming Limits
- AWS has strict limits on resource name lengths (typically 128 characters)
- Avoid using the full stack name in resource names
- Use the pattern `$stage-webhooks-*` for resource names
- Example: `dev-webhooks-kafka` instead of `kafka-webhook-bridge-dev-kafka`

### Key Differences from Local Setup
- Using AWS Application Load Balancer (ALB) instead of nginx-proxy for SSL termination and Kafka proxying
- ALB handles both HTTPS (443) for webhooks and TCP (29095) for Kafka
- No need for separate nginx container in ECS

## Domain Structure

The deployment uses a base domain (e.g., harperstaging.com) with two hardcoded subdomains:
- `webhooks.harperstaging.com`: Webhook service endpoint (HTTPS/443)
- `kafka.harperstaging.com`: Kafka ALB endpoint (TCP/29095)

The base domain is passed as a parameter to the CloudFormation template, while the subdomains are hardcoded in the template.

## Architecture Components

### 1. Network Configuration

```
[Client] -> [ALB (Public)] -> [ECS Service (Private)] -> [Kafka (Private)] -> [Webhook Service (Private)]
```

- **VPC Configuration**:
  - Private subnets for all ECS services (webhook and Kafka)
  - Public subnets only for ALB
  - VPC Endpoints for AWS services (ECR, CloudWatch, etc.) - configured in the existing VPC stack
  - NAT Gateway for outbound traffic from private subnets

- **Security Groups**:
  - ALB: Allow inbound 443/29095 from internet
  - ECS Service: Allow inbound from ALB
  - Kafka: Allow inbound from ECS Service
  - Webhook Service: Allow inbound from ECS Service

### 2. Load Balancer Configuration

The ALB is configured with two listeners:
1. HTTPS (443) for webhook endpoints
2. TCP (29095) for Kafka connections

```yaml
  ALB:
    Type: AWS::ElasticLoadBalancingV2::LoadBalancer
    Properties:
      Name: !Sub ${Stage}-webhooks-alb
      Scheme: internet-facing
      Subnets:
        - !Ref PublicSubnet1
        - !Ref PublicSubnet2
      SecurityGroups:
        - !Ref ALBSecurityGroup

  WebhookListener:
    Type: AWS::ElasticLoadBalancingV2::Listener
    Properties:
      LoadBalancerArn: !Ref ALB
      Port: 443
      Protocol: HTTPS
      Certificates:
        - CertificateArn: !Ref CertificateArn
      DefaultActions:
        - Type: forward
          TargetGroupArn: !Ref WebhookTargetGroup

  KafkaListener:
    Type: AWS::ElasticLoadBalancingV2::Listener
    Properties:
      LoadBalancerArn: !Ref ALB
      Port: !Ref KafkaExternalPort
      Protocol: TCP
      DefaultActions:
        - Type: forward
          TargetGroupArn: !Ref KafkaTargetGroup
```

### 3. Kafka Configuration

The Kafka broker will be configured with multiple listeners, similar to our Docker setup:

```properties
# Listener Configuration
listeners=CONTROLLER://:9093,INTERNAL://0.0.0.0:9094,BROKER://0.0.0.0:9095,PROXY://0.0.0.0:9096
advertised.listeners=INTERNAL://${KafkaService.Name}.${ECSCluster.Name}.internal:9094,BROKER://${KafkaService.Name}.${ECSCluster.Name}.internal:9095,PROXY://${KafkaLoadBalancer.DNSName}:${KafkaExternalPort}
listener.security.protocol.map=CONTROLLER:PLAINTEXT,INTERNAL:SASL_PLAINTEXT,BROKER:SASL_PLAINTEXT,PROXY:SASL_PLAINTEXT
```

Key differences from Docker setup:
- Using ALB instead of nginx-proxy
- Using Route53 for DNS resolution with hardcoded subdomains
- Internal communication via ECS service discovery
- BROKER listener for inter-broker communication (though we only have one broker)
- INTERNAL listener for communication by the webhook service inside the network
- PROXY listener for external access through the load balancer

### 4. ECS Service Configuration

- **Task Definition**:
  - Single task running both Kafka and Webhook services
  - Shared volume for Kafka data
  - Environment variables for SASL configuration
  - Health checks for both services
  - Internal communication via localhost (same task)
  - VPC Endpoints for AWS service access

- **Service Configuration**:
  - Private subnet placement for all services
  - VPC Endpoints for ECR, CloudWatch, etc.
  - Proper security group rules
  - Fargate launch type
  - Application Load Balancer for SSL termination
  - Health check grace period



### 5. Security Configuration

- **SSL/TLS**:
  - ACM certificate for HTTPS
  - Proper security protocols
  - Strong cipher suites

- **Authentication**:
  - SASL/PLAIN for Kafka
  - Basic auth for webhooks
  - IAM roles for AWS services

- **Network Security**:
  - Private subnets for services
  - VPC Endpoints for AWS services
  - Proper security group rules
  - No direct internet access for services

### 6. Monitoring and Logging

- CloudWatch Logs for all containers
- Container Insights for ECS
- Basic health checks
- ALB access logs

## Deployment Process

1. Deploy the VPC stack first (includes VPC Endpoints)
2. Deploy this stack with references to VPC resources
3. Configure DNS records
4. Test connectivity and functionality

### Deployment Scripts

The deployment is handled by two scripts in the `aws` directory:

1. `deploy.sh`: For initial deployment
   ```bash
   ./aws/deploy.sh <subdomain> [image_tag]
   ```

2. `update.sh`: For updating existing deployments
   ```bash
   ./aws/update.sh <subdomain> [image_tag]
   ```

Both scripts will:
- Set up the required environment variables
- Deploy/update the CloudFormation stack
- Configure DNS records
- Verify the deployment

## Rollback Strategy

1. Keep previous stack version
2. Monitor deployment health
3. Automatic rollback on failure
4. Manual rollback if needed

## Maintenance Procedures

1. Regular security updates
2. Certificate renewal
3. Log rotation
4. Performance monitoring

## Cost Considerations

1. Fargate pricing
2. ALB costs
3. VPC Endpoint costs
4. CloudWatch costs

## Limitations and Constraints

1. Single region deployment
2. Single availability zone
3. No cross-region replication
4. Limited scalability options

## Next Steps

1. Create the CloudFormation template based on this structure
2. Update the deployment scripts to handle the new configuration
3. Test the deployment in a staging environment
4. Document the deployment process and rollback procedures 

## Local Development Setup
For local development, the service uses a hardcoded external port of 29095 for Kafka connections. This port is used in:
- Nginx stream configuration
- Docker Compose port mappings
- Kafka advertised listeners

To start the local development environment:
```bash
docker-compose up -d
```

The Kafka broker will be accessible at:
- External: `kafka.harperconcierge.dev:29095`
- Internal: `localhost:29095`

## CloudFormation Deployment
The CloudFormation template allows configuring the external Kafka port through the `KafkaExternalPort` parameter. This is different from the local development setup which uses a hardcoded port.

### Parameters
- `KafkaExternalPort`: The external port for Kafka connections (default: 29095)
- `Environment`: The deployment environment (dev/staging/prod)
- `DomainName`: The domain name for the service
- `KafkaUsername`: Username for Kafka authentication
- `KafkaPassword`: Password for Kafka authentication
- `WebhookUsername`: Username for webhook authentication
- `WebhookPassword`: Password for webhook authentication

### Resources Created
1. VPC and Network Infrastructure
   - VPC with public and private subnets
   - Internet Gateway
   - NAT Gateway
   - Security Groups

2. ECS Cluster
   - Fargate cluster for running containers
   - Task definitions for each service
   - Service definitions with auto-scaling

3. RDS Database
   - PostgreSQL instance for storing webhook events
   - Security group for database access

4. Application Load Balancer
   - SSL certificate management
   - Target groups for each service
   - Listener rules for routing traffic

5. CloudWatch Logs
   - Log groups for each service
   - Log retention policies

6. IAM Roles and Policies
   - Task execution roles
   - Service roles
   - Security policies

## Deployment Steps
1. Create an SSL certificate in AWS Certificate Manager
2. Deploy using the provided scripts:
   ```bash
   # For initial deployment
   ./aws/deploy.sh <subdomain> [image_tag]

   # For updates
   ./aws/update.sh <subdomain> [image_tag]
   ```

3. Verify the deployment:
   - Check CloudFormation events
   - Verify service health in ECS
   - Test webhook endpoints
   - Monitor CloudWatch logs

## Monitoring and Maintenance
- CloudWatch metrics for service health
- Log aggregation and analysis
- Automated backups for RDS
- Auto-scaling based on load

## Security Considerations
- All traffic is encrypted using SSL/TLS
- Authentication required for all endpoints
- Secrets managed through AWS Secrets Manager
- Network isolation using VPC and security groups

## Troubleshooting
1. Check CloudWatch logs for service errors
2. Verify security group rules
3. Test connectivity to Kafka broker
4. Monitor ECS service events
5. Review ALB target group health

## Cleanup
To remove the deployment:
```bash
aws cloudformation delete-stack --stack-name kafka-webhook-bridge
```

Note: This will not delete the SSL certificate or any manually created resources. 