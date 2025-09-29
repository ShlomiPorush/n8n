# n8n High-Availability Docker Compose Setup

Production-ready n8n deployment with queue mode, multiple webhook handlers, worker processes, and Traefik reverse proxy integration.

## 🏗️ Architecture

This setup provides a scalable n8n infrastructure with:

- **1 Main Instance**: UI and management
- **7 Webhook Handlers**: Dedicated webhook processing for high throughput
- **7 Workers**: Parallel workflow execution
- **Redis**: Queue management and job distribution
- **RedisInsight**: Redis monitoring and management UI
- **Traefik Integration**: Automatic HTTPS and load balancing

```
                                    ┌─────────────┐
                                    │   Traefik   │
                                    │  (External) │
                                    └──────┬──────┘
                                           │
                    ┌──────────────────────┼──────────────────────┐
                    │                      │                      │
              ┌─────▼─────┐         ┌─────▼─────┐         ┌─────▼─────┐
              │  n8n-main │         │  Webhook  │         │   Redis   │
              │    (UI)   │         │  Handler  │         │  Insight  │
              └─────┬─────┘         │   x7      │         └───────────┘
                    │               └─────┬─────┘
                    │                     │
              ┌─────▼─────────────────────▼─────┐
              │          Redis Queue            │
              └─────┬───────────────────────┬───┘
                    │                       │
              ┌─────▼─────┐           ┌─────▼─────┐
              │  Worker 1 │    ...    │  Worker 7 │
              └───────────┘           └───────────┘
```

## 📋 Prerequisites

- Docker Engine 20.10+
- Docker Compose 2.0+
- External PostgreSQL database
- Traefik reverse proxy (configured separately)
- Domain with DNS configured

### Required External Networks

```bash
docker network create traefik
docker network create n8n
docker network create dns  # Optional, for custom DNS
```

### Required External Volume

```bash
docker volume create n8nRedis
```

## 🚀 Quick Start

### 1. Clone and Setup

```bash
git clone <repository-url>
cd n8n-docker-compose
```

### 2. Create Environment File

Create a `.env` file in the project root:

```bash
# Domain Configuration
DOMAIN=example.com
SUB=n8n

# DNS Server (optional)
DNS_SERVER=8.8.8.8

# Timezone
TIMEZONE=UTC

# Database Configuration
PG_HOST=your-postgres-host
PG_DB=n8n
PG_USER=n8n
PG_PASS=your-secure-password

# n8n Encryption Key (IMPORTANT: Generate a secure random key!)
N8N_ENCRYPTION_KEY=your-encryption-key-min-10-chars

# SMTP Configuration (optional)
SMTP_HOST=smtp.example.com
SMTP_PORT=587
SMTP_SSL=true
SMTP_SENDER=n8n@example.com
# SMTP_USER=username
# SMTP_PASS=password
```

### 3. Generate Encryption Key

```bash
# Generate a secure encryption key
openssl rand -base64 32
```

⚠️ **CRITICAL**: Store this key securely. If lost, you cannot decrypt your credentials!

### 4. Create Required Directories

```bash
mkdir -p data logs redisinsight
```

### 5. Launch Services

```bash
docker-compose up -d
```

### 6. Check Status

```bash
docker-compose ps
docker-compose logs -f n8n-main
```

## 📁 Directory Structure

```
.
├── docker-compose.yml
├── .env
├── data/              # n8n data (workflows, credentials, etc.)
├── logs/              # n8n log files
└── redisinsight/      # RedisInsight data
```

## 🔧 Configuration

### Scaling

Adjust the number of webhooks and workers by modifying the `docker-compose.yml`:

**To add more webhooks:**
```yaml
n8n-webhook8:
  <<: *shared-webhook
  container_name: n8nWebhook8
  hostname: n8nWebhook8
```

**To add more workers:**
```yaml
n8n-worker8:
  container_name: n8nWorker8
  hostname: n8nWorker8
  <<: *shared-worker
```

Remember to update dependencies in `x-shared-worker` section.

### Performance Tuning

**Payload Size**
```yaml
N8N_PAYLOAD_SIZE_MAX=500  # MB
```

**Data Retention**
```yaml
EXECUTIONS_DATA_MAX_AGE=336  # hours (14 days)
```

**Log Rotation**
```yaml
N8N_LOG_FILE_MAXSIZE=5      # MB per file
N8N_LOG_FILE_MAXCOUNT=30    # Keep 30 files
```

### Traefik Labels

The setup assumes Traefik is configured with:
- Middleware `secured@file`: Authentication for main UI
- Middleware `default-headers@file`: Security headers
- Middleware `headers-authentik@file`: Authentik authentication (for RedisInsight)

Adjust these according to your Traefik configuration.

## 🌐 Access Points

After deployment, access n8n at:

- **Main UI**: `https://n8n.example.com`
- **Webhook API**: `https://api.example.com/service/...`
- **Webhook Test**: `https://api.example.com/test/...`
- **RedisInsight**: `https://redis.example.com`

## 🔐 Security Considerations

### Critical Security Steps

1. **Change default encryption key** in `.env`
2. **Use strong database passwords**
3. **Enable MFA** (set `N8N_MFA_ENABLED=true`)
4. **Configure firewall rules** to restrict database access
5. **Regular backups** of data directory and database
6. **Keep Docker images updated**
7. **Use Traefik authentication** for UI access
8. **Secure SMTP credentials** if using authenticated SMTP

### Security Features Enabled

- `no-new-privileges:true`: Prevents privilege escalation
- `N8N_ENFORCE_SETTINGS_FILE_PERMISSIONS=true`: File permission checks
- HTTPS only (via Traefik)
- Production mode enabled

## 📊 Monitoring

### View Logs

```bash
# All services
docker-compose logs -f

# Specific service
docker-compose logs -f n8n-main
docker-compose logs -f n8n-worker1

# Last 100 lines
docker-compose logs --tail=100 n8n-main
```

### Check Health

```bash
# Service status
docker-compose ps

# Health checks
docker inspect n8n-main | grep -A 10 Health
```

### Redis Monitoring

Access RedisInsight at `https://redis.example.com` to:
- Monitor queue performance
- View active jobs
- Check memory usage
- Analyze slow operations

## 🔄 Queue Mode Explained

This setup uses **Queue Mode** for optimal performance:

- **Main Process**: Handles UI and workflow management
- **Webhook Handlers**: Process incoming webhook requests immediately
- **Workers**: Execute workflows from the queue in parallel

Benefits:
- High availability (if one worker fails, others continue)
- Horizontal scaling (add more workers as needed)
- Better resource utilization
- Improved response times for webhooks

## 🐛 Troubleshooting

### Service Won't Start

```bash
# Check logs
docker-compose logs service-name

# Verify environment variables
docker-compose config

# Check database connectivity
docker-compose exec n8n-main ping -c 3 $PG_HOST
```

### Database Connection Issues

```bash
# Test PostgreSQL connection
docker run --rm -it postgres:15 psql -h PG_HOST -U PG_USER -d PG_DB
```

### Redis Connection Issues

```bash
# Check Redis health
docker-compose exec n8nredis redis-cli ping

# View Redis info
docker-compose exec n8nredis redis-cli info
```

### Webhook Not Responding

1. Check webhook handler logs
2. Verify Traefik routing rules
3. Test webhook endpoint directly
4. Check Redis queue for pending jobs

### Worker Not Processing Jobs

```bash
# Check worker logs
docker-compose logs -f n8n-worker1

# Verify Redis connection
docker-compose exec n8n-worker1 nc -zv n8nredis 6379
```

## 🔄 Maintenance

### Update n8n

```bash
# Pull latest images
docker-compose pull

# Recreate containers
docker-compose up -d

# Clean old images
docker image prune -f
```

### Backup

```bash
# Backup data directory
tar -czf n8n-backup-$(date +%Y%m%d).tar.gz data/

# Backup database (example with pg_dump)
docker exec postgres-container pg_dump -U n8n n8n > n8n-db-backup.sql
```

### Restore

```bash
# Stop services
docker-compose down

# Restore data
tar -xzf n8n-backup-YYYYMMDD.tar.gz

# Restore database
docker exec -i postgres-container psql -U n8n n8n < n8n-db-backup.sql

# Start services
docker-compose up -d
```

## 📈 Performance Tips

1. **Adjust worker count** based on CPU cores (typically 1-2 workers per core)
2. **Monitor Redis memory** and adjust if needed
3. **Use execution data pruning** to keep database size manageable
4. **Enable filesystem binary data mode** for better performance with large files
5. **Separate webhook handlers** from workers for better response times
6. **Use external PostgreSQL** with proper indexes for better performance

## 🛠️ Advanced Configuration

### Custom Node Modules

Mount custom nodes directory:
```yaml
volumes:
  - ./custom-nodes:/home/node/.n8n/custom
```

### External Secrets

Use Docker secrets or environment variables from external sources:
```yaml
environment:
  - N8N_ENCRYPTION_KEY_FILE=/run/secrets/n8n_encryption_key
secrets:
  - n8n_encryption_key
```

## 📚 Additional Resources

- [n8n Documentation](https://docs.n8n.io/)
- [n8n Queue Mode](https://docs.n8n.io/hosting/scaling/queue-mode/)
- [Traefik Documentation](https://doc.traefik.io/traefik/)
- [Redis Documentation](https://redis.io/documentation)

## 🤝 Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## ⚠️ Disclaimer

This is a production-ready setup, but always:
- Test in a staging environment first
- Review security settings for your specific use case
- Keep regular backups
- Monitor performance and adjust as needed
