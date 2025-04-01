const { Kafka } = require('kafkajs');
const chalk = require('chalk');

// Get topics from environment or use default list
const topics = (process.env.KAFKA_TOPICS || 'harper-concierge-dev, harper-centra-dev, harper-bigcommerce-dev, harper-salesforce-dev, harper-magento-dev').split(',');
const kafkaPort = process.env.KAFKA_EXTERNAL_PORT || '29095';
const kafkaBroker = process.env.KAFKA_BROKER || 'kafka.harperconcierge.dev';

console.log(chalk.blue(`Attempting to connect to Kafka at ${kafkaBroker}:${kafkaPort}`));
console.log(chalk.blue(`Will subscribe to topics: ${topics.join(', ')}`));

// Create the kafka instance
const kafka = new Kafka({
  clientId: 'kafka-consumer',
  brokers: [`${kafkaBroker}:${kafkaPort}`],
  ssl: {
    rejectUnauthorized: false,
    servername: kafkaBroker,  // matches wildcard cert
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

async function consumeMessages() {
  const consumer = kafka.consumer({ groupId: 'test-group' });

  try {
    // Connect to the broker
    await consumer.connect();
    console.log(chalk.green('Connected to Kafka broker'));

    // Subscribe to all specified topics
    for (const topic of topics) {
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
  }
}

// Handle SIGINT to gracefully shutdown
process.on('SIGINT', async () => {
  console.log(chalk.yellow('\nGracefully shutting down...'));
  process.exit(0);
});

// Run the consumer
console.log(chalk.blue('Starting Kafka consumer...'));
consumeMessages().catch(error => {
  console.error(chalk.red('Fatal error:'), error);
  process.exit(1);
});