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
const username = process.env.KAFKA_BROKER_USERNAME ?? 'webhook';
const password = process.env.KAFKA_BROKER_PASSWORD ?? 'webhook';
const defaultTopic = process.env.DEFAULT_TOPIC || 'webhook-events';

// Kafka configuration
const kafkaConfig = {
  clientId: process.env.KAFKA_CLIENT_ID || 'webhook-service',
  brokers,
  ssl: false,
  // ssl: {
  //   rejectUnauthorized: false,
  //   servername: brokers[0].split(':')[0],
  //   minVersion: 'TLSv1.2' as const,
  //   maxVersion: 'TLSv1.2' as const
  // },
  sasl: {
    mechanism: 'plain' as const,
    username,
    password,
  },
  connectionTimeout: 3000,
  authenticationTimeout: 3000,
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

// Handle graceful shutdown
const shutdown = async (signal: string) => {
  logger.info(`Received ${signal}, starting graceful shutdown...`);

  try {
    // Disconnect producer
    await producer.disconnect();
    logger.info('Kafka producer disconnected');

    // Close server
    server.close(() => {
      logger.info('HTTP server closed');
      process.exit(0);
    });
  } catch (error) {
    logger.error('Error during shutdown:', error);
    process.exit(1);
  }
};

// Set up signal handlers
process.on('SIGTERM', () => shutdown('SIGTERM'));
process.on('SIGINT', () => shutdown('SIGINT'));

// Prevent process from hanging on unhandled rejections
process.on('unhandledRejection', (reason, promise) => {
  logger.error('Unhandled Rejection at:', promise, 'reason:', reason);
  process.exit(1);
});

// Prevent process from hanging on uncaught exceptions
process.on('uncaughtException', (error) => {
  logger.error('Uncaught Exception:', error);
  process.exit(1);
});

const app = express();
app.use(express.json());

// Basic auth middleware
const basicAuth = expressBasicAuth({
  users: { [process.env.WEBHOOK_USERNAME || 'admin']: process.env.WEBHOOK_PASSWORD || 'admin-secret' },
  challenge: true
});

// Simple health check for local task health
app.get('/health', (req, res) => {
  res.json({ status: 'ok' });
});

// Enhanced health check for target group
app.get('/health/ready', async (req, res) => {
  const health = {
    status: 'ok',
    timestamp: new Date().toISOString(),
    checks: {
      http: 'ok',
      kafka: 'ok'
    }
  };

  try {
    // Check Kafka connection
    const admin = kafka.admin();
    await admin.connect();
    await admin.disconnect();
  } catch (error) {
    health.status = 'error';
    health.checks.kafka = 'error';
    logger.error('Health check failed: Kafka connection error', { error });
  }

  // If any check failed, return 503
  if (health.status === 'error') {
    return res.status(503).json(health);
  }

  res.json(health);
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
      '/health/ready': {
        methods: ['GET'],
        description: 'Enhanced health check for target group',
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
        examples: {
          'Shopify Order Creation': {
            path: '/webhooks/shopify/orders/create',
            method: 'POST',
            payload: {
              "id": 123456789,
              "email": "customer@example.com",
              "created_at": "2024-03-20T10:00:00Z",
              "total_price": "99.99",
              "currency": "USD",
              "line_items": [
                {
                  "title": "Product Name",
                  "quantity": 1,
                  "price": "99.99"
                }
              ]
            }
          },
          'Stripe Payment Success': {
            path: '/webhooks/stripe/events/payment_intent.succeeded',
            method: 'POST',
            payload: {
              "id": "evt_123456789",
              "type": "payment_intent.succeeded",
              "created": 1710936000,
              "data": {
                "object": {
                  "id": "pi_123456789",
                  "amount": 9999,
                  "currency": "usd",
                  "customer": "cus_123456789",
                  "status": "succeeded"
                }
              }
            }
          },
          'Square Order Update': {
            path: '/webhooks/square/orders/update',
            method: 'POST',
            payload: {
              "merchant_id": "M123456789",
              "type": "order.updated",
              "event_id": "evt_123456789",
              "created_at": "2024-03-20T10:00:00Z",
              "data": {
                "type": "order",
                "id": "order_123456789",
                "object": {
                  "order": {
                    "id": "order_123456789",
                    "state": "COMPLETED",
                    "total_money": {
                      "amount": 9999,
                      "currency": "USD"
                    }
                  }
                }
              }
            }
          },
          'Centra Fulfillment': {
            path: '/webhooks/centra/fulfillment/created',
            method: 'POST',
            payload: {
              "event": "fulfillment.created",
              "timestamp": "2024-03-20T10:00:00Z",
              "data": {
                "orderId": "ORD-123456789",
                "fulfillmentId": "FUL-123456789",
                "status": "created",
                "items": [
                  {
                    "orderItemId": "ITEM-123456789",
                    "sku": "PROD-123456789",
                    "quantity": 1,
                    "warehouse": "MAIN-WAREHOUSE"
                  }
                ],
                "shipping": {
                  "carrier": "DHL",
                  "trackingNumber": "1234567890",
                  "trackingUrl": "https://www.dhl.com/tracking/1234567890"
                }
              }
            }
          },
          'BigCommerce Fulfillment': {
            path: '/webhooks/bigcommerce/orders/fulfillment',
            method: 'POST',
            payload: {
              "scope": "store/order/fulfillment",
              "store_id": 12345,
              "producer": "stores/12345",
              "hash": "abc123def456",
              "created_at": 1710936000,
              "data": {
                "type": "order",
                "id": 123456789,
                "order_id": 123456789,
                "status_id": 11,
                "status": "Shipped",
                "shipping_provider": "FedEx",
                "tracking_number": "1234567890",
                "tracking_carrier": "fedex",
                "tracking_url": "https://www.fedex.com/tracking/1234567890",
                "items": [
                  {
                    "order_product_id": 987654321,
                    "product_id": 123456789,
                    "sku": "PROD-123456789",
                    "quantity": 1
                  }
                ]
              }
            }
          }
        }
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
app.all('/:topicName/*', basicAuth, async (req, res) => {
	console.log(req.path, 'Requested');
  try {
    const topicNameRaw = req.params.topicName;

    // Validate and sanitize topic name
    const validation = validateTopicName(topicNameRaw);
    if (!validation.valid || !validation.sanitized) {
      return res.status(400).json({ error: validation.error });
    }

    const topicName = validation.sanitized;

    // Get the remaining path after /topicName/
    const webhookPath = req.url.substring(`/${topicNameRaw}/`.length);

    // Create message with body if applicable
    const message: any = {
      method: req.method,
      headers: req.headers,
      path: webhookPath,
      query: req.originalUrl.split('?')[1] || '', // Extracts the query string,
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
const server = app.listen(port, async () => {
  try {
    // Connect to Kafka
    await producer.connect();
    logger.info(`Server running on port ${port}`);
    logger.info('Connected to Kafka');
  } catch (error) {
    logger.error('Failed to start server:', error);
    process.exit(1);
  }
});