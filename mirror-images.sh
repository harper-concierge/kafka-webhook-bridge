#!/bin/bash

# Set variables
AWS_REGION="eu-west-1"  # Update this if your region is different
ECR_REGISTRY="$(aws ecr describe-registry --query 'registryId' --output text).dkr.ecr.${AWS_REGION}.amazonaws.com"
CONFLUENT_VERSION="7.3.0"

# Create repositories if they don't exist
for repo in cp-zookeeper cp-kafka cp-schema-registry cp-kafka-rest; do
    aws ecr describe-repositories --repository-names "${repo}" 2>/dev/null || \
    aws ecr create-repository --repository-name "${repo}" \
        --image-scanning-configuration scanOnPush=true \
        --encryption-configuration encryptionType=AES256
done

# Login to ECR
aws ecr get-login-password --region "${AWS_REGION}" | docker login --username AWS --password-stdin "${ECR_REGISTRY}"

# Function to mirror an image
mirror_image() {
    local source_image="confluentinc/$1:$2"
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
mirror_image "cp-zookeeper" "${CONFLUENT_VERSION}"
mirror_image "cp-kafka" "${CONFLUENT_VERSION}"
mirror_image "cp-schema-registry" "${CONFLUENT_VERSION}"
mirror_image "cp-kafka-rest" "${CONFLUENT_VERSION}"

# Output the new image URLs for updating CloudFormation
echo -e "\nUpdate your CloudFormation template with these image URLs:"
echo "Zookeeper: ${ECR_REGISTRY}/cp-zookeeper:${CONFLUENT_VERSION}"
echo "Kafka: ${ECR_REGISTRY}/cp-kafka:${CONFLUENT_VERSION}"
echo "Schema Registry: ${ECR_REGISTRY}/cp-schema-registry:${CONFLUENT_VERSION}"
echo "REST Proxy: ${ECR_REGISTRY}/cp-kafka-rest:${CONFLUENT_VERSION}"
