#!/bin/bash

# Exit on error
set -e

# Check required arguments
if [ $# -lt 2 ]; then
    echo "Usage: $0 <command> <stage> [image_tag]"
    echo "Example: $0 create-stack staging"
    exit 1
fi

command="$1"
STAGE="$2"
IMAGE_TAG="$3"
changeset=""

# Check required environment variables
required_vars=(
    "KAFKA_BROKER_USERNAME"
    "KAFKA_BROKER_PASSWORD"
    "WEBHOOK_USERNAME"
    "WEBHOOK_PASSWORD"
    "KAFKA_HOSTED_ZONE_ID"
)

missing_vars=()
for var in "${required_vars[@]}"; do
    if [ -z "${!var}" ]; then
        missing_vars+=("$var")
    fi
done

if [ ${#missing_vars[@]} -ne 0 ]; then
    echo "Error: Missing required environment variables:"
    printf '%s\n' "${missing_vars[@]}"
    echo "Please run: aws/get_env_vars.sh > .envrc && direnv allow"
    exit 1
fi

# Initialize parameters array
allParameters=()

echo "Setting Env Vars"

# Generate deployment timestamp
DEPLOYMENT_TIMESTAMP=$(date +%Y%m%d%H%M%S)

# Generate broker_id based on deployment timestamp (ensuring it's under 2147483647)
# Using last 9 digits of timestamp to ensure we stay under the limit
BROKER_ID=$(echo $DEPLOYMENT_TIMESTAMP | tail -c 9)

# Add parameters from environment variables
allParameters+=("ParameterKey=KafkaUsername,ParameterValue='${KAFKA_BROKER_USERNAME}'")
allParameters+=("ParameterKey=KafkaPassword,ParameterValue='${KAFKA_BROKER_PASSWORD}'")
allParameters+=("ParameterKey=WebhookUsername,ParameterValue='${WEBHOOK_USERNAME}'")
allParameters+=("ParameterKey=WebhookPassword,ParameterValue='${WEBHOOK_PASSWORD}'")
allParameters+=("ParameterKey=HostedZoneId,ParameterValue='${KAFKA_HOSTED_ZONE_ID}'")
allParameters+=("ParameterKey=BrokerId,ParameterValue='${BROKER_ID}'")
allParameters+=("ParameterKey=DeploymentTimestamp,ParameterValue='${DEPLOYMENT_TIMESTAMP}'")

# Add container image parameters only if they are set
if [ -n "${KAFKA_CONTAINER_IMAGE:-}" ]; then
  allParameters+=("ParameterKey=KafkaImage,ParameterValue='${KAFKA_CONTAINER_IMAGE}'")
  echo "Overriding Kafka image with ${KAFKA_CONTAINER_IMAGE}"
fi

# Get the domain name from the HostedZoneId
DOMAIN_NAME=$(aws route53 get-hosted-zone --id "$KAFKA_HOSTED_ZONE_ID" --query 'HostedZone.Name' --output text | sed 's/\.$//')
FULL_DOMAIN="${DOMAIN_NAME}"

# Add domain name parameter
allParameters+=("ParameterKey=DomainName,ParameterValue='${FULL_DOMAIN}'")

# Note: This matches the KafkaServiceDiscovery name
INTERNAL_KAFKA_DOMAIN="kafka-internal.${STAGE}.webhooks-bridge.local"
allParameters+=("ParameterKey=KafkaInternalDnsName,ParameterValue='${INTERNAL_KAFKA_DOMAIN}'")

# Handle image tag
if [ "$command" = "update-stack" ]; then
    if [ -z "$IMAGE_TAG" ]; then
        # Get current image tag from running task
        task_arn=$(aws ecs list-tasks --cluster "${STAGE}-webhooks-cluster" --desired-status RUNNING --family "${STAGE}-webhooks-service" --query 'taskArns[0]' --output text)
        if [ -n "$task_arn" ]; then
            task_definition_arn=$(aws ecs describe-tasks --cluster "${STAGE}-webhooks-cluster" --tasks "$task_arn" --query "tasks[0].taskDefinitionArn" --output text)
            IMAGE_TAG=$(aws ecs describe-task-definition --task-definition "$task_definition_arn" --query "taskDefinition.containerDefinitions[0].image" --output text | awk -F ':' '{print $NF}')
            echo "Using current image tag: $IMAGE_TAG"
        else
            echo "Error: No running tasks found to get current image tag"
            exit 1
        fi
    else
        echo "Using provided image tag: $IMAGE_TAG"
    fi
fi
allParameters+=("ParameterKey=WebhookImageTag,ParameterValue='${IMAGE_TAG}'")

echo "Using domain: ${FULL_DOMAIN} ${IMAGE_TAG}"

# Handle change set creation
if [ "$command" = "create-change-set" ]; then
    epoch=$(awk 'BEGIN{srand(); print srand()}')
    echo "Creating ChangeSet: kafka-webhook-bridge-$epoch"
    changeset="--change-set-name kafka-webhook-bridge-$epoch"
fi

# Deploy the stack
# shellcheck disable=SC2086
aws cloudformation "$command" \
    --stack-name "kafka-webhook-bridge-stack" \
    --template-body file://kafka-webhook-bridge-stack.yml \
    --parameters \
        "${allParameters[@]}" \
        "ParameterKey=Stage,ParameterValue=${STAGE}" \
    --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM CAPABILITY_AUTO_EXPAND \
    --region eu-west-1 $changeset

#echo "Waiting for stack update to finish..."
#aws cloudformation wait stack-update-complete --stack-name "kafka-webhook-bridge-stack"
#echo "Stack update finished."
