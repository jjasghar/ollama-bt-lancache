# Deployment Guide

This guide explains how to deploy and use the Ollama BitTorrent Lancache system.

## Prerequisites

- **Go 1.21+** - For building the server application
- **Python 3.8+** - For client scripts and BitTorrent operations
- **Git** - For cloning the tracker repository
- **Network access** - Between machines for BitTorrent communication

## Quick Start

### 1. Clone and Setup

```bash
git clone <your-repo-url>
cd ollama-bt-lancache

# Make scripts executable
chmod +x quickstart.sh install.sh seeder.py test.py
```

### 2. Start Services

#### Option A: Using Quick Start Script (Recommended)
```bash
# Linux/macOS
./quickstart.sh

# Windows (PowerShell as Administrator)
.\quickstart.ps1
```

#### Option B: Manual Setup
```bash
# Setup tracker
make setup-tracker-auto

# Build server
make build

# Start tracker (in one terminal)
make run-tracker

# Start server (in another terminal)
make run-server
```

#### Option C: Using Docker
```bash
docker-compose up -d
```

### 3. Verify Installation

```bash
# Run comprehensive tests
python3 test.py

# Or test individual components
make test
```

## Service Architecture

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   BitTorrent    │    │   Main Server   │    │   Client       │
│   Tracker       │◄──►│   Application   │◄──►│   Machines     │
│   (Port 8080)   │    │   (Port 8081)   │    │                │
└─────────────────┘    └─────────────────┘    └─────────────────┘
```

## Configuration

### Server Configuration

Create `~/.ollama-bt-lancache.yaml`:

```yaml
server:
  port: 8081
  host: "0.0.0.0"

tracker:
  url: "http://YOUR_TRACKER_IP:8080"

models_dir: "~/.ollama/models"

logging:
  level: "info"
```

### Environment Variables

- `TRACKER_URL` - BitTorrent tracker URL
- `MODELS_DIR` - Path to Ollama models directory
- `PORT` - Server port (default: 8080)

## Client Installation

### Windows (PowerShell)

```powershell
# Run as Administrator
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
Invoke-WebRequest -Uri "http://YOUR_SERVER_IP:8081/install.ps1" -OutFile "install.ps1"
.\install.ps1 --Model "llama2:7b" --Server "http://YOUR_SERVER_IP:8081"
```

### Linux/macOS (Bash)

```bash
# Download and run installation script
curl -sSL "http://YOUR_SERVER_IP:8081/install.sh" | bash

# Or download and run manually
curl -sSL "http://YOUR_SERVER_IP:8081/install.sh" -o install.sh
chmod +x install.sh
./install.sh llama2:7b "http://YOUR_SERVER_IP:8081"
```

### Manual Python Setup

```bash
# Create virtual environment
python3 -m venv ~/.ollama-bt-venv
source ~/.ollama-bt-venv/bin/activate

# Install dependencies
pip install -r requirements.txt

# Download seeder script
curl -sSL "http://YOUR_SERVER_IP:8081/seeder.py" -o seeder.py

# Download models
python3 seeder.py --server "http://YOUR_SERVER_IP:8081" --download-all
```

## Usage Examples

### Download Specific Model

```bash
python3 seeder.py --server "http://YOUR_SERVER_IP:8081" --model "llama2:7b"
```

### Download All Models

```bash
python3 seeder.py --server "http://YOUR_SERVER_IP:8081" --download-all
```

### Seed Local Model

```bash
python3 seeder.py --server "http://YOUR_SERVER_IP:8081" --seed "~/.ollama/models/llama2:7b"
```

### List Available Models

```bash
python3 seeder.py --server "http://YOUR_SERVER_IP:8081" --list
```

## Monitoring and Management

### Web Interface

Access the web interface at `http://YOUR_SERVER_IP:8081` to:
- View available models
- Download torrent files
- Access installation scripts
- Monitor system status

### API Endpoints

- `GET /api/models` - List available models
- `GET /api/models/{name}/torrent` - Download torrent file for specific model
- `GET /install.ps1` - PowerShell installation script
- `GET /install.sh` - Bash installation script
- `GET /seeder.py` - Python seeder script

### Logs

- Server logs: `server/server.log`
- Tracker logs: `tracker/tracker.log`
- Docker logs: `docker-compose logs -f`

## Troubleshooting

### Common Issues

1. **Port conflicts**: Ensure ports 8080 (tracker) and 8081 (server) are available
2. **Firewall**: Allow BitTorrent ports 6881-6891 and HTTP ports 8080-8081
3. **Python dependencies**: Install with `pip install -r requirements.txt`
4. **Permission issues**: Run installation scripts with appropriate privileges

### Debug Mode

```bash
# Enable debug logging
export LOG_LEVEL=debug
./server/ollama-bt-lancache

# Or modify config file
logging:
  level: "debug"
```

### Network Diagnostics

```bash
# Test connectivity
python3 test.py

# Check ports
netstat -tulpn | grep :808

# Test BitTorrent ports
nc -zv localhost 6881-6891
```

## Security Considerations

- **Private tracker**: This system uses a private BitTorrent tracker
- **Network isolation**: Keep the tracker on internal networks only
- **Authentication**: Consider adding authentication for production use
- **Rate limiting**: Configure rate limits to prevent abuse

## Performance Tuning

### BitTorrent Settings

```yaml
bittorrent:
  piece_size: 1048576      # 1MB pieces
  max_connections: 200     # Max peer connections
  max_uploads: 10          # Max upload slots
  upload_limit: 0          # 0 = unlimited
  download_limit: 0        # 0 = unlimited
```

### Server Settings

```yaml
server:
  port: 8081
  host: "0.0.0.0"
  max_requests: 1000       # Max concurrent requests
```

## Scaling

### Multiple Trackers

Run multiple tracker instances for redundancy:

```yaml
tracker:
  urls:
    - "http://tracker1:8080"
    - "http://tracker2:8080"
    - "http://tracker3:8080"
```

### Load Balancing

Use a load balancer (nginx, haproxy) in front of multiple server instances.

### Geographic Distribution

Deploy trackers and servers in different geographic locations for better peer discovery.

## Backup and Recovery

### Configuration Backup

```bash
# Backup configuration
cp ~/.ollama-bt-lancache.yaml ~/.ollama-bt-lancache.yaml.backup

# Backup models (if needed)
rsync -av ~/.ollama/models/ /backup/ollama-models/
```

### Disaster Recovery

1. Restore configuration files
2. Rebuild tracker and server
3. Restore model data (if needed)
4. Verify connectivity and functionality

## Support

For issues and questions:
1. Check the troubleshooting section
2. Review logs for error messages
3. Run the test script: `python3 test.py`
4. Check network connectivity and firewall settings
