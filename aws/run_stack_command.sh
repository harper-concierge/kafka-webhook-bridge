#!/bin/bash

set -e

# Check required arguments
if [ $# -lt 2 ]; then
    echo "Usage: $0 <command> <subdomain> [image_tag]"
    echo "Example: $0 create-stack webhook-bridge"
    exit 1
fi

command="$1"
SUBDOMAIN="$2"
IMAGE_TAG="$3"
STAGE="production"  # Default to production
changeset=""

# Check required environment variables
required_vars=(
    "KAFKA_USERNAME"
    "KAFKA_PASSWORD"
    "WEBHOOK_USERNAME"
    "WEBHOOK_PASSWORD"
    "HOSTED_ZONE_ID"
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

# Add parameters from environment variables
allParameters+=("ParameterKey=KafkaUsername,ParameterValue='${KAFKA_USERNAME}'")
allParameters+=("ParameterKey=KafkaPassword,ParameterValue='${KAFKA_PASSWORD}'")
allParameters+=("ParameterKey=WebhookUsername,ParameterValue='${WEBHOOK_USERNAME}'")
allParameters+=("ParameterKey=WebhookPassword,ParameterValue='${WEBHOOK_PASSWORD}'")
allParameters+=("ParameterKey=HostedZoneId,ParameterValue='${HOSTED_ZONE_ID}'")

# Get the domain name from the HostedZoneId
DOMAIN_NAME=$(aws route53 get-hosted-zone --id "$HOSTED_ZONE_ID" --query 'HostedZone.Name' --output text | sed 's/\.$//')
FULL_DOMAIN="${SUBDOMAIN}.${DOMAIN_NAME}"

echo "Using domain: ${FULL_DOMAIN}"

# Add domain name parameter
allParameters+=("ParameterKey=DomainName,ParameterValue='${FULL_DOMAIN}'")

# Handle image tag
if [ "$command" = "update-stack" ]; then
    if [ -z "$IMAGE_TAG" ]; then
        # Get current image tag from running task
        task_arn=$(aws ecs list-tasks --cluster "kafka-api-bridge-cluster" --desired-status RUNNING --family kafka-webhook-bridge --query 'taskArns[0]' --output text)
        if [ -n "$task_arn" ]; then
            task_definition_arn=$(aws ecs describe-tasks --cluster "kafka-api-bridge-cluster" --tasks "$task_arn" --query "tasks[0].taskDefinitionArn" --output text)
            IMAGE_TAG=$(aws ecs describe-task-definition --task-definition "$task_definition_arn" --query "taskDefinition.containerDefinitions[0].image" --output text | awk -F ':' '{print $NF}')
            echo "Using current image tag: $IMAGE_TAG"
        else
            echo "Error: No running tasks found to get current image tag"
            exit 1
        fi
    else
        echo "Using provided image tag: $IMAGE_TAG"
    fi
    allParameters+=("ParameterKey=WebhookImageTag,ParameterValue='${IMAGE_TAG}'")
fi

# Handle change set creation
if [ "$command" = "create-change-set" ]; then
    epoch=$(awk 'BEGIN{srand(); print srand()}')
    echo "Creating ChangeSet: kafka-api-bridge-$epoch"
    changeset="--change-set-name kafka-api-bridge-$epoch"
fi

# Deploy the stack
# shellcheck disable=SC2086

aws cloudformation "$command" \
    --stack-name "kafka-api-bridge-stack" \
    --template-body file://kafka-webhook-bridge-stack.yml \
    --parameters \
        "${allParameters[@]}" \
        "ParameterKey=Stage,ParameterValue=${STAGE}" \
    --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM CAPABILITY_AUTO_EXPAND \
    --region eu-west-1 $changeset

#echo "Waiting for stack update to finish..."
#aws cloudformation wait stack-update-complete --stack-name "kafka-api-bridge-stack"
#echo "Stack update finished."
