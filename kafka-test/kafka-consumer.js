const { Kafka } = require('kafkajs');
const chalk = require('chalk');

// Get topics from environment or use default list
const topics = (process.env.KAFKA_TOPICS || 'shopify,stripe,centra,bigcommerce').split(',');
const kafkaBrokerUrl = process.env.KAFKA_BROKER_URL || 'kafka.harperconcierge.dev:29095';
const kafkaUsername = process.env.KAFKA_BROKER_USERNAME || 'webhook';
const kafkaPassword = process.env.KAFKA_BROKER_PASSWORD || 'webhook';

console.log(chalk.blue(`Attempting to connect to Kafka at ${kafkaBroker}:${kafkaPort}`));
console.log(chalk.blue(`Will subscribe to topics: ${topics.join(', ')}`));
console.log(chalk.blue(`Using username: ${kafkaUsername}`));
const servername = kafkaBrokerUrl.split(':')[0];

// Create the kafka instance
const kafka = new Kafka({
  clientId: 'kafka-consumer',
  brokers: [kafkaBrokerUrl],
  ssl: {
    rejectUnauthorized: true,
    servername,
    minVersion: 'TLSv1.2',
    maxVersion: 'TLSv1.2'
  },
  sasl: {
    mechanism: 'plain',
    username: kafkaUsername,
    password: kafkaPassword,
  },
  connectionTimeout: 5000,
  authenticationTimeout: 5000,
  retry: {
    initialRetryTime: 100,
    retries: 3
  }
});

// Format JSON for pretty printing
function formatJson(json) {
  try {
    if (typeof json === 'string') {
      json = JSON.parse(json);
    }
    return JSON.stringify(json, null, 2);
  } catch (e) {
    return json;
  }
}

async function checkTopics() {
  const admin = kafka.admin();
  try {
    await admin.connect();
    console.log(chalk.blue('\nChecking topics...'));

    const existingTopics = await admin.listTopics();
    console.log(chalk.blue('Existing topics:', existingTopics.join(', ')));

    for (const topic of topics) {
      if (existingTopics.includes(topic)) {
        const topicMetadata = await admin.fetchTopicMetadata({ topics: [topic] });
        const metadata = topicMetadata.topics[0];
        console.log(chalk.green(`\nTopic ${chalk.yellow(topic)} exists:`));
        console.log(chalk.white(`  Partitions: ${metadata.partitions.length}`));
        console.log(chalk.white(`  Replication Factor: ${metadata.partitions[0].replicas.length}`));

        // Get topic offsets
        const offsets = await admin.fetchTopicOffsets(topic);
        console.log(chalk.white('  Partitions:'));
        offsets.forEach(offset => {
          console.log(chalk.white(`    Partition ${offset.partition}:`));
          console.log(chalk.white(`      Latest: ${offset.high}`));
          console.log(chalk.white(`      Earliest: ${offset.low}`));
          console.log(chalk.white(`      Messages: ${offset.high - offset.low}`));
        });
      } else {
        console.log(chalk.yellow(`\nTopic ${chalk.red(topic)} does not exist`));
      }
    }
  } catch (error) {
    console.error(chalk.red('Error checking topics:'), error);
  } finally {
    await admin.disconnect();
  }
}

async function consumeMessages() {
  const consumer = kafka.consumer({ groupId: 'test-group' });

  try {
    // Connect to the broker
    await consumer.connect();
    console.log(chalk.green('\nConnected to Kafka broker'));

    // Subscribe to all specified topics
    for (const topic of topics) {
      console.log(chalk.green(`Subscribing to ${chalk.yellow(topic)} topic`));
      await consumer.subscribe({ topic, fromBeginning: true });
      console.log(chalk.green(`Subscribed to ${chalk.yellow(topic)} topic`));
    }

    // Start consuming messages
    await consumer.run({
      eachMessage: async ({ topic, partition, message }) => {
        try {
          const value = message.value.toString();
          const parsedValue = JSON.parse(value);

          // Print message header with topic and partition info
          console.log('\n' + '='.repeat(80));
          console.log(chalk.cyan(`TOPIC: ${chalk.bold(topic)} | PARTITION: ${partition} | OFFSET: ${message.offset}`));
          console.log(chalk.cyan(`TIMESTAMP: ${new Date(parseInt(message.timestamp)).toISOString()}`));
          console.log('-'.repeat(80));

          // Print HTTP method and path if available
          if (parsedValue.method) {
            console.log(chalk.magenta(`METHOD: ${chalk.bold(parsedValue.method)}`));
          }

          if (parsedValue.path) {
            console.log(chalk.magenta(`PATH: ${chalk.bold(parsedValue.path)}`));
          }

          if (parsedValue.event) {
            console.log(chalk.magenta(`EVENT: ${chalk.bold(parsedValue.event)}`));
          }

          // Print message body
          console.log(chalk.yellow('MESSAGE BODY:'));
          if (parsedValue.body) {
            console.log(chalk.white(formatJson(parsedValue.body)));
          } else {
            // If there's no separate body field, show the whole message
            // but exclude some common fields to avoid duplication
            const { headers, method, path, timestamp, ...rest } = parsedValue;
            console.log(chalk.white(formatJson(rest)));
          }

          console.log('='.repeat(80));
        } catch (parseError) {
          console.error(chalk.red('Error parsing message:'), parseError);
          console.log(chalk.yellow('Raw message:'), message.value.toString());
        }
      },
    });
  } catch (error) {
    console.error(chalk.red('Error:'), error);
    if (error.name === 'KafkaJSSASLAuthenticationError') {
      console.error(chalk.red('Authentication failed. Please check your credentials:'));
      console.error(chalk.yellow('Username:'), kafkaUsername);
      console.error(chalk.yellow('Password:'), kafkaPassword ? '[hidden]' : 'not set');
      console.error(chalk.yellow('Broker:'), `${kafkaBroker}:${kafkaPort}`);
    }
    process.exit(1);
  }
}

// Handle SIGINT to gracefully shutdown
process.on('SIGINT', async () => {
  console.log(chalk.yellow('\nGracefully shutting down...'));
  process.exit(0);
});

// Run the consumer
console.log(chalk.blue('Starting Kafka consumer...'));
checkTopics().then(() => {
  return consumeMessages();
}).catch(error => {
  console.error(chalk.red('Fatal error:'), error);
  process.exit(1);
});