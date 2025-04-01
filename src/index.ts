import express from 'express';
import expressBasicAuth from 'express-basic-auth';
import { Kafka } from 'kafkajs';
import winston from 'winston';

// Configure logger
const logger = winston.createLogger({
  level: process.env.LOG_LEVEL || 'info',
  format: winston.format.combine(
    winston.format.timestamp(),
    winston.format.json()
  ),
  transports: [
    new winston.transports.Console()
  ]
});

// Environment variables
const brokers = process.env.KAFKA_BROKERS?.split(',') ?? ['kafka:9094'];
const username = process.env.KAFKA_USERNAME ?? process.env.KAFKA_BROKER_USERNAME ?? 'webhook';
const password = process.env.KAFKA_PASSWORD ?? process.env.KAFKA_BROKER_PASSWORD ?? 'webhook';
const defaultTopic = process.env.DEFAULT_TOPIC || 'webhook-events';

// Kafka configuration
const kafkaConfig = {
  clientId: process.env.KAFKA_CLIENT_ID || 'webhook-service',
  brokers,
  ssl: false,
  sasl: {
    mechanism: 'plain' as const,
    username,
    password,
  },
  retry: {
    initialRetryTime: 100,
    retries: 8
  }
};

logger.info('Kafka configuration', {
  kafkaConfig: {
    ...kafkaConfig,
    sasl: { ...kafkaConfig.sasl, password: '***' },
    brokers,
    defaultTopic
  }
});

const kafka = new Kafka(kafkaConfig);
const producer = kafka.producer();

const app = express();
app.use(express.json());

// Basic auth middleware
const basicAuth = expressBasicAuth({
  users: { [process.env.WEBHOOK_USERNAME || 'admin']: process.env.WEBHOOK_PASSWORD || 'admin-secret' },
  challenge: true
});

// Health check endpoint
app.get('/health', (req, res) => {
	console.log('/health - requested');
  res.json({ status: 'ok' });
});

// Documentation endpoint
app.get('/', (req, res) => {
	console.log('/ - requested');
  res.json({
    service: 'Kafka Webhook Bridge',
    description: 'Service that forwards webhook payloads to Kafka topics',
    apiVersion: '1.0.0',
    endpoints: {
      '/health': {
        methods: ['GET'],
        description: 'Health check endpoint',
        authentication: 'None'
      },
      '/webhooks/:topicName/*': {
        methods: ['GET', 'POST', 'PUT', 'DELETE', 'PATCH', 'OPTIONS'],
        description: 'Dynamic webhook endpoint - posts to specified topic',
        authentication: 'Basic Auth',
        parameters: {
          topicName: 'The name of the Kafka topic (alphanumeric, underscores, hyphens, dots)',
          '*': 'Arbitrary path that will be included in the message'
        },
        example: '/webhooks/github-events/repository/push'
      }
    }
  });
});

// Function to validate and sanitize topic name
function validateTopicName(topicName: string): { valid: boolean; sanitized?: string; error?: string } {
  // Check basic format
  if (!topicName || topicName.length === 0) {
    return { valid: false, error: 'Topic name cannot be empty' };
  }

  // Check for invalid characters
  if (!topicName.match(/^[a-zA-Z0-9_-]+$/)) {
    return { valid: false, error: 'Topic name can only contain alphanumeric characters, underscores and hyphens' };
  }

  // Check length
  if (topicName.length > 249) {
    return { valid: false, error: 'Topic name cannot exceed 249 characters' };
  }

  // Sanitize the topic name to be safe
  const sanitized = topicName.replace(/^\./, '').replace(/\.$/, '');

  return { valid: true, sanitized };
}

// Dynamic topic webhook endpoint
app.all('/webhooks/:topicName/*', basicAuth, async (req, res) => {
	console.log(req.path, 'Requested');
  try {
    const topicNameRaw = req.params.topicName;

    // Validate and sanitize topic name
    const validation = validateTopicName(topicNameRaw);
    if (!validation.valid || !validation.sanitized) {
      return res.status(400).json({ error: validation.error });
    }

    const topicName = validation.sanitized;

    // Get the remaining path after /webhooks/topicName/
    const webhookPath = req.url.substring(`/webhooks/${topicNameRaw}/`.length);

    // Create message with body if applicable
    const message: any = {
      method: req.method,
      headers: req.headers,
      path: webhookPath,
      query: req.query,
      timestamp: new Date().toISOString()
    };

    // Add body if it exists (for POST, PUT, PATCH)
    if (req.body && Object.keys(req.body).length > 0) {
      message.body = req.body;
    }

    await producer.send({
      topic: topicName,
      messages: [{ value: JSON.stringify(message) }]
    });

    logger.info(`Message sent to Kafka topic '${topicName}'`, { method: req.method, path: webhookPath });
    res.json({ status: 'ok', topic: topicName, path: webhookPath, method: req.method });
  } catch (error: any) {
    if (error.name === 'KafkaJSNumberOfRetriesExceeded' && error.message.includes('Topic does not exist')) {
      return res.status(404).json({ error: `Topic ${req.params.topicName} does not exist` });
    }
    logger.error('Error processing webhook with dynamic topic', { error });
    res.status(500).json({ error: 'Internal server error' });
  }
});

// Start server
const port = process.env.PORT || 3000;
app.listen(port, async () => {
  try {
    await producer.connect();
    logger.info(`Webhook service listening on port ${port}`);
    logger.info('Connected to Kafka');
  } catch (error) {
    logger.error('Failed to connect to Kafka', { error });
    process.exit(1);
  }
});

// Graceful shutdown
process.on('SIGTERM', async () => {
  logger.info('SIGTERM signal received, closing connections');
  await producer.disconnect();
  process.exit(0);
});