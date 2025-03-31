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
const autoCreateTopics = process.env.AUTO_CREATE_TOPICS !== 'false'; // default to true
const topicPartitions = parseInt(process.env.TOPIC_PARTITIONS || '3', 10);
const replicationFactor = parseInt(process.env.REPLICATION_FACTOR || '1', 10);

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
    autoCreateTopics,
    defaultTopic
  } 
});

const kafka = new Kafka(kafkaConfig);
const producer = kafka.producer();
const admin = kafka.admin();

// Topic existence cache
const topicExistsCache = new Map<string, boolean>();
const TOPIC_CACHE_TTL = 60 * 1000; // 1 minute

// Initialize metrics
const metrics = {
  requestsTotal: 0,
  requestsByTopic: new Map<string, number>(),
  requestsByMethod: new Map<string, number>(),
  errors: 0,
  lastError: null as Error | null,
  startTime: new Date(),
  topicsCreated: 0
};

// Function to increment request count
function incrementRequestMetric(topic: string, method: string) {
  metrics.requestsTotal++;
  
  const topicCount = metrics.requestsByTopic.get(topic) || 0;
  metrics.requestsByTopic.set(topic, topicCount + 1);
  
  const methodCount = metrics.requestsByMethod.get(method) || 0;
  metrics.requestsByMethod.set(method, methodCount + 1);
}

// Function to record error
function recordError(error: Error) {
  metrics.errors++;
  metrics.lastError = error;
}

// Function to ensure topic exists with caching
async function ensureTopicExists(topic: string): Promise<boolean> {
  // Check cache first
  if (topicExistsCache.has(topic)) {
    return topicExistsCache.get(topic)!;
  }

  try {
    const topics = await admin.listTopics();
    
    if (!topics.includes(topic)) {
      if (!autoCreateTopics) {
        logger.warn(`Topic ${topic} does not exist and auto-creation is disabled`);
        
        // Cache the negative result
        topicExistsCache.set(topic, false);
        setTimeout(() => {
          topicExistsCache.delete(topic);
        }, TOPIC_CACHE_TTL);
        
        return false;
      }
      
      logger.info(`Topic ${topic} does not exist, creating it`);
      await admin.createTopics({
        topics: [{ 
          topic, 
          numPartitions: topicPartitions, 
          replicationFactor: replicationFactor 
        }],
      });
      logger.info(`Topic ${topic} created successfully`);
      metrics.topicsCreated++;
    }
    
    // Update cache
    topicExistsCache.set(topic, true);
    setTimeout(() => {
      topicExistsCache.delete(topic);
    }, TOPIC_CACHE_TTL);
    
    return true;
  } catch (error) {
    logger.error(`Failed to ensure topic ${topic} exists`, { error });
    recordError(error as Error);
    
    // Update cache with negative result (also cached to prevent hammering)
    topicExistsCache.set(topic, false);
    setTimeout(() => {
      topicExistsCache.delete(topic);
    }, TOPIC_CACHE_TTL);
    
    return false;
  }
}

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

// Documentation endpoint
app.get('/', (req, res) => {
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
      },
      '/metrics': {
        methods: ['GET'],
        description: 'Metrics endpoint',
        authentication: 'None'
      }
    }
  });
});

// Original webhook endpoint (backward compatibility)
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
      topic: defaultTopic,
      messages: [{ value: JSON.stringify(message) }]
    });

    // Track metrics
    incrementRequestMetric(defaultTopic, req.method);
    
    logger.info('Message sent to Kafka', { topic: defaultTopic });
    res.json({ status: 'ok', topic: defaultTopic });
  } catch (error) {
    recordError(error as Error);
    logger.error('Error processing webhook', { error });
    res.status(500).json({ error: 'Internal server error' });
  }
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
  try {
    const topicNameRaw = req.params.topicName;
    
    // Validate and sanitize topic name
    const validation = validateTopicName(topicNameRaw);
    if (!validation.valid) {
      return res.status(400).json({ error: validation.error });
    }
    
    const topicName = validation.sanitized!;
    
    // Get the remaining path after /webhooks/topicName/
    const webhookPath = req.url.substring(`/webhooks/${topicNameRaw}/`.length);
    
    // Ensure topic exists before sending
    const topicExists = await ensureTopicExists(topicName);
    if (!topicExists) {
      return res.status(500).json({ error: 'Failed to create or verify topic' });
    }

    // Create message with body if applicable
    const message: any = {
      method: req.method,
      headers: req.headers,
      path: webhookPath,
      originalUrl: req.originalUrl,
      query: req.query,
      timestamp: new Date().toISOString()
    };

    // Add body if it exists (for POST, PUT, PATCH)
    if (req.body && Object.keys(req.body).length > 0) {
      message.body = req.body;
      if (req.body.event) {
        message.event = req.body.event;
      }
    }

    await producer.send({
      topic: topicName,
      messages: [{ value: JSON.stringify(message) }]
    });

    // Track metrics
    incrementRequestMetric(topicName, req.method);
    
    logger.info(`Message sent to Kafka topic '${topicName}'`, { method: req.method, path: webhookPath });
    res.json({ status: 'ok', topic: topicName, path: webhookPath, method: req.method });
  } catch (error) {
    recordError(error as Error);
    logger.error('Error processing webhook with dynamic topic', { error });
    res.status(500).json({ error: 'Internal server error' });
  }
});

// Metrics endpoint
app.get('/metrics', (req, res) => {
  // Calculate uptime
  const uptime = new Date().getTime() - metrics.startTime.getTime();
  
  // Format metrics for output
  const formattedMetrics = {
    service: 'kafka-webhook-bridge',
    version: '1.0.0',
    uptime: `${Math.floor(uptime / 1000 / 60 / 60)}h ${Math.floor((uptime / 1000 / 60) % 60)}m ${Math.floor((uptime / 1000) % 60)}s`,
    requests: {
      total: metrics.requestsTotal,
      byTopic: Object.fromEntries(metrics.requestsByTopic),
      byMethod: Object.fromEntries(metrics.requestsByMethod)
    },
    errors: {
      count: metrics.errors,
      lastError: metrics.lastError ? metrics.lastError.message : null
    },
    kafka: {
      brokers: brokers.length,
      topicsCreated: metrics.topicsCreated,
      cachedTopics: topicExistsCache.size
    },
    memory: {
      rss: `${Math.round(process.memoryUsage().rss / 1024 / 1024)} MB`,
      heapTotal: `${Math.round(process.memoryUsage().heapTotal / 1024 / 1024)} MB`,
      heapUsed: `${Math.round(process.memoryUsage().heapUsed / 1024 / 1024)} MB`
    }
  };
  
  res.json(formattedMetrics);
});

// Start server
const port = process.env.PORT || 3000;
app.listen(port, async () => {
  try {
    await producer.connect();
    await admin.connect();
    
    // Ensure the default topic exists
    await ensureTopicExists(defaultTopic);
    
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
  await admin.disconnect();
  process.exit(0);
});