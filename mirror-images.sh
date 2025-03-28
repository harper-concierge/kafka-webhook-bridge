#!/bin/bash

# Set variables
AWS_REGION="eu-west-1"  # Update this if your region is different
ECR_REGISTRY="$(aws ecr describe-registry --query 'registryId' --output text).dkr.ecr.${AWS_REGION}.amazonaws.com"
CONFLUENT_VERSION="3.6"

# Create repositories if they don't exist
for repo in kafka; do
    aws ecr describe-repositories --repository-names "${repo}" 2>/dev/null || \
    aws ecr create-repository --repository-name "${repo}" \
        --image-scanning-configuration scanOnPush=true \
        --encryption-configuration encryptionType=AES256
done

# Login to ECR
aws ecr get-login-password --region "${AWS_REGION}" | docker login --username AWS --password-stdin "${ECR_REGISTRY}"

# Function to mirror an image
mirror_image() {
    local source_image="bitnami/$1:$2"
    local target_image="${ECR_REGISTRY}/$1:$2"

    echo "Pulling ${source_image} (amd64)..."
    docker pull --platform linux/amd64 "${source_image}"

    echo "Tagging ${source_image} as ${target_image}..."
    docker tag "${source_image}" "${target_image}"

    echo "Pushing ${target_image}..."
    docker push "${target_image}"

    echo "Done mirroring $1"
}

# Mirror images
echo "Starting image mirroring..."
mirror_image "kafka" "${CONFLUENT_VERSION}"

# Output the new image URLs for updating CloudFormation
echo -e "\nUpdate your CloudFormation template with these image URLs:"
echo "Kafka: ${ECR_REGISTRY}/kafka:${CONFLUENT_VERSION}"
