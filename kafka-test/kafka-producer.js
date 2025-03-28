const { Kafka } = require('kafkajs');

const kafka = new Kafka({
  clientId: 'test-producer',
  brokers: ['kafka.harperconcierge.dev:443'],
  ssl: {
    rejectUnauthorized: false
  },
  sasl: {
    mechanism: 'plain',
    username: process.env.KAFKA_BROKER_USERNAME,
    password: process.env.KAFKA_BROKER_PASSWORD
  }
});

const producer = kafka.producer();

async function sendMessage() {
  try {
    await producer.connect();
    console.log('Connected to Kafka');

    const topic = 'test-topic';
    const message = {
      key: 'test-key',
      value: JSON.stringify({
        timestamp: new Date().toISOString(),
        message: 'Hello from test producer!'
      })
    };

    await producer.send({
      topic,
      messages: [message]
    });

    console.log('Message sent successfully');
  } catch (error) {
    console.error('Error:', error);
  } finally {
    await producer.disconnect();
  }
}

sendMessage(); 