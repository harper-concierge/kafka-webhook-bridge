const { Kafka } = require('kafkajs');

const topic = 'webhook-events';
const kafkaPort = process.env.KAFKA_EXTERNAL_PORT || '29095';

// Create the kafka instance
const kafka = new Kafka({
  clientId: 'kafka-consumer',
  brokers: [`kafka.harperconcierge.dev:${kafkaPort}`],
  ssl: {
    rejectUnauthorized: false,
    servername: 'kafka.harperconcierge.dev',  // matches wildcard cert
    minVersion: 'TLSv1.2',
    maxVersion: 'TLSv1.2'
  },
  sasl: {
    mechanism: 'plain',
    username: process.env.KAFKA_BROKER_USERNAME || 'webhook',
    password: process.env.KAFKA_BROKER_PASSWORD || 'webhook',
  },
  connectionTimeout: 3000,
  authenticationTimeout: 3000,
  retry: {
    initialRetryTime: 100,
    retries: 3
  }
});

async function consumeMessages() {
  const consumer = kafka.consumer({ groupId: 'test-group' });

  try {
    // Connect to the broker
    await consumer.connect();
    console.log('Connected to Kafka broker');

    // Subscribe to the test topic
    await consumer.subscribe({ topic, fromBeginning: true });
    console.log(`Subscribed to ${topic} topic`);

    // Start consuming messages
    await consumer.run({
      eachMessage: async ({ topic, partition, message }) => {
        console.log({
          topic,
          partition,
          offset: message.offset,
          value: message.value.toString(),
          timestamp: message.timestamp,
        });
      },
    });
  } catch (error) {
    console.error('Error:', error);
  }
}

// Run the consumer
consumeMessages().catch(console.error);