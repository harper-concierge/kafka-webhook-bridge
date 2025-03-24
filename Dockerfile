FROM node:20-alpine

WORKDIR /app

# Copy package files
COPY package*.json ./

# Install dependencies including dev dependencies for TypeScript compilation
RUN npm ci

# Copy source code
COPY src/ src/
COPY tsconfig.json ./

# Build TypeScript
RUN npm run build

# Remove dev dependencies and source files
RUN npm ci --production
RUN rm -rf src/ tsconfig.json

# Copy Kafka configurations
COPY kafka/config /etc/kafka

# Expose port
EXPOSE 3000

# Start the application
CMD ["npm", "start"] 