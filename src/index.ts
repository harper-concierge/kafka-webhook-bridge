import express from 'express';
import expressBasicAuth from 'express-basic-auth';
import { Kafka } from 'kafkajs';
import winston from 'winston';

// Configure logger
const logger = winston.createLogger({
  level: 'info',
  format: winston.format.combine(
    winston.format.timestamp(),
    winston.format.json()
  ),
  transports: [
    new winston.transports.Console()
  ]
});

const brokers = process.env.KAFKA_BROKERS?.split(',') ?? ['localhost:9092'];
const username = process.env.KAFKA_BROKER_USERNAME ?? 'webhook';
const password = process.env.KAFKA_BROKER_PASSWORD ?? 'webhook';


const kafkaConfig = {
  clientId: process.env.KAFKA_CLIENT_ID || 'webhook-service',
  brokers,
  ssl: false,
  sasl: {
    mechanism: 'plain' as const,
    username,
    password,
  },
};

console.log(kafkaConfig);
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
  res.json({ status: 'ok' });
});

// Webhook endpoint
app.post('/webhook', basicAuth, async (req, res) => {
  try {
    const message = {
      event: req.body.event,
      body: req.body,
      method: req.method,
      headers: req.headers,
      timestamp: new Date().toISOString()
    };

    await producer.send({
      topic: 'webhook-events',
      messages: [{ value: JSON.stringify(message) }]
    });

    logger.info('Message sent to Kafka', { message });
    res.json({ status: 'ok' });
  } catch (error) {
    logger.error('Error processing webhook', { error });
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