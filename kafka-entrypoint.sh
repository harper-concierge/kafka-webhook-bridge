#!/bin/bash

# Create JAAS config file
cat > /etc/kafka/kafka_server_jaas.conf << EOF
KafkaServer {
    org.apache.kafka.common.security.scram.ScramLoginModule required
    username="${KAFKA_USERNAME}"
    password="${KAFKA_PASSWORD}";
};
EOF

# Create the admin user
kafka-configs --zookeeper localhost:2181 \
    --alter --add-config "SCRAM-SHA-512=[password=${KAFKA_PASSWORD}]" \
    --entity-type users --entity-name "${KAFKA_USERNAME}"

# Start Kafka
exec /etc/confluent/docker/run 