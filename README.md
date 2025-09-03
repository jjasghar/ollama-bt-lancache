# Ollama BitTorrent Lancache

A BitTorrent-based distribution system for Ollama models, enabling horizontal scaling and efficient peer-to-peer model sharing across networks.

## 🎯 Overview

Ollama BitTorrent Lancache transforms the traditional point-to-point model distribution into a scalable BitTorrent network. Instead of a single server serving all clients, models are distributed through a peer-to-peer network where each client can also serve as a seed, dramatically improving download speeds and reducing server load.

## ✨ Key Features

- **🌐 Web Interface**: Browse and download available models
- **📡 BitTorrent Tracker**: Manages peer connections and swarm coordination
- **🤖 Auto Seeding**: Automatically seeds all available models
- **📱 Cross-Platform Clients**: PowerShell and Bash scripts for easy client setup
- **🔄 Dynamic Model Discovery**: Automatically detects new models in `~/.ollama/models`
- **⚡ Horizontal Scaling**: Multiple seeds per model for faster downloads
- **🎛️ Individual Model Torrents**: Each model gets its own optimized torrent file
- **🌱 Auto-Seeding Clients**: Clients automatically become seeders after download

## 🏗️ Architecture

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Web Server    │    │ BitTorrent      │    │   Auto Seeder   │
│   (Port 8080)   │    │ Tracker         │    │   (Monitoring)  │
│                 │    │ (Port 8081)     │    │                 │
│ • Model API     │    │ • Peer Mgmt     │    │ • Torrent Scan  │
│ • Web Interface │    │ • Swarm Coord   │    │ • Auto Seeding  │
│ • Torrent Gen   │    │ • Announce/Scrape│   │ • Process Mgmt  │
└─────────────────┘    └─────────────────┘    └─────────────────┘
         │                       │                       │
         └───────────────────────┼───────────────────────┘
                                 │
                    ┌─────────────────┐
                    │   BitTorrent    │
                    │     Swarm       │
                    │                 │
                    │ • Multiple Seeds│
                    │ • Peer-to-Peer  │
                    │ • Fast Downloads│
                    │ • Auto-Seeding  │
                    └─────────────────┘
```

## 🚀 Quick Start

### Prerequisites

- **Go 1.19+** (for server and tracker)
- **Python 3.8+** (for client scripts)
- **Ollama** with models in `~/.ollama/models`

### 1. Clone and Setup

```bash
git clone https://github.com/jjasghar/ollama-bt-lancache.git
cd ollama-bt-lancache

# Create Python virtual environment
python3 -m venv venv
source venv/bin/activate
pip install libtorrent requests

# Build the server and tracker
cd server
go mod tidy
go build -o ollama-bt-lancache
cd ../tracker/privtracker
go mod tidy
go build -o tracker
cd ../..
```

### 2. Start the System

```bash
# Start everything with one command
./start_system.sh
```

This will start:
- **BitTorrent Tracker** on port 8081
- **Web Server** on port 8080 (with dynamic IP detection)
- **Auto Seeder** for all existing models

The system will automatically detect your local IP and use it for all services.

### 3. Stop the System

```bash
# Stop all services (preserve torrent files)
./stop_system.sh

# Stop all services and clean up torrent files
./stop_system.sh --clean
```

### 4. Access the Web Interface

Open your browser to `http://YOUR_IP:8080` to:
- Browse available models
- Download torrent files
- Get client installation scripts

## 📋 Available Models

The system automatically discovers models from `~/.ollama/models` and creates individual torrent files for each model. Each torrent contains only the files specific to that model (manifest + layer files), making them much smaller and more efficient.

Example models:
- **granite3.3:8b** (~4.7 GB)
- **granite-code:8b** (~4.4 GB)

## 🛠️ System Management

### Management Scripts

```bash
# Start complete system
./start_system.sh

# Start just seeding (if services already running)
./start_seeding.sh

# Stop just seeding (keep web server/tracker running)
./stop_seeding.sh

# Stop everything (preserve torrent files)
./stop_system.sh

# Stop everything and clean up torrent files
./stop_system.sh --clean
```

## 🔧 Manual Setup

### Start Services Individually

```bash
# Terminal 1: Start BitTorrent Tracker
cd tracker/privtracker
PORT=8081 ./tracker

# Terminal 2: Start Web Server
cd server
./ollama-bt-lancache

# Terminal 3: Start Auto Seeder
python3 auto_seeder.py --tracker http://YOUR_IP:8081 --start-existing-only
```

### Auto Seeder Options

```bash
# Monitor and auto-seed all torrents
python3 auto_seeder.py --tracker http://YOUR_IP:8081

# Start seeders for existing torrents only
python3 auto_seeder.py --tracker http://YOUR_IP:8081 --start-existing-only

# Check status
python3 auto_seeder.py --tracker http://YOUR_IP:8081 --status
```

## 👥 Client Installation

### Linux/macOS (Bash)

```bash
# Download and run the Bash script
curl -sSL "http://YOUR_SERVER_IP:8080/install.sh" | bash -s -- --model <model-name>

# List available models
curl -sSL "http://YOUR_SERVER_IP:8080/install.sh" | bash -s -- --list

# Test mode (download to temporary directory)
curl -sSL "http://YOUR_SERVER_IP:8080/install.sh" | bash -s -- --test --model <model-name>
```

### Manual Client Usage

```bash
# List available models
python3 client.py --server http://YOUR_SERVER_IP:8080 --list

# Download a specific model (auto-seeds after completion)
python3 client.py --server http://YOUR_SERVER_IP:8080 --model granite3.3:8b --output ./downloads

# Download using a torrent file
python3 client.py --file model.torrent --output ./downloads
```

## 🛠️ Configuration

### Server Configuration

The server automatically:
- Discovers models from `~/.ollama/models`
- Creates individual torrent files for each model by parsing Docker manifests
- Includes only the specific layer files for each model
- Serves torrent files via web API
- Generates client installation scripts with correct IP addresses

### Tracker Configuration

The BitTorrent tracker:
- Uses dynamic announce intervals based on swarm size
- Handles both localhost and external IP connections
- Provides announce and scrape endpoints
- Manages peer coordination for each model

### Auto Seeder Configuration

```bash
# Custom models directory
python3 auto_seeder.py --models-dir ~/.ollama/models --tracker http://YOUR_IP:8081

# Custom check interval
python3 auto_seeder.py --tracker http://YOUR_IP:8081 --check-interval 30
```

## 📊 Monitoring

### Web Interface

Visit `http://YOUR_IP:8080` to see:
- Available models with sizes
- Download links for torrent files
- Client installation scripts

### Auto Seeder Status

```bash
python3 auto_seeder.py --tracker http://YOUR_IP:8081 --status
```

### Tracker Status

```bash
# Check tracker response
curl -s "http://YOUR_IP:8081/ollama/announce?info_hash=HASH&peer_id=TEST&port=6881&uploaded=0&downloaded=0&left=0&compact=1"
```

## 🔄 Workflow

1. **Model Discovery**: Server scans `~/.ollama/models` for models
2. **Manifest Parsing**: Reads Docker manifests to identify model-specific files
3. **Individual Torrent Creation**: Creates optimized torrent files for each model
4. **Auto Seeding**: Auto seeder starts seeding all available models
5. **Client Download**: Clients download torrents and join the swarm
6. **Auto-Seeding**: Clients automatically become seeders after download
7. **Peer-to-Peer**: Multiple seeds serve the same model for faster downloads

## 🎯 Benefits

- **⚡ Faster Downloads**: Multiple seeds per model
- **📈 Horizontal Scaling**: More clients = more seeds
- **🔄 Automatic Distribution**: New models automatically seeded
- **💾 Bandwidth Efficiency**: Peer-to-peer distribution
- **🛡️ Fault Tolerance**: Multiple seeds provide redundancy
- **🎛️ Optimized Metadata**: Individual model torrents are much smaller
- **🌱 Auto-Seeding**: Clients automatically contribute to the swarm

## 🚨 Troubleshooting

### Common Issues

**Port Already in Use**
```bash
# Check what's using the port
lsof -i :8080
lsof -i :8081

# Kill the process
kill -9 PID
```

**Models Not Found**
```bash
# Check if models exist
ollama list
ls -la ~/.ollama/models/

# Restart the server to re-scan
./stop_system.sh --clean && ./start_system.sh
```

**Seeder Not Starting**
```bash
# Check virtual environment
source venv/bin/activate
pip list | grep libtorrent

# Check torrent files
ls -la ~/.ollama/models/*.torrent
```

**Client Can't Find Peers**
```bash
# Check if seeders are running
ps aux | grep seeder.py

# Check tracker status
curl -s "http://YOUR_IP:8081/ollama/scrape?info_hash=HASH"
```

### Logs and Debugging

```bash
# Check server logs
cd server
./ollama-bt-lancache

# Check tracker logs
cd tracker/privtracker
PORT=8081 ./tracker

# Check seeder status
python3 auto_seeder.py --tracker http://YOUR_IP:8081 --status
```

## 📁 Project Structure

```
ollama-bt-lancache/
├── server/                 # Go web server
│   ├── main.go            # Main server application
│   └── go.mod             # Go dependencies
├── tracker/               # BitTorrent tracker
│   └── privtracker/       # meehow/privtracker
├── client.py              # Python BitTorrent client (auto-seeding)
├── seeder.py              # Python seeding script
├── auto_seeder.py         # Automatic seeding manager
├── start_system.sh        # System startup script (dynamic IP)
├── stop_system.sh         # System shutdown script
├── install.sh             # Linux/macOS client installer
└── README.md              # This file
```

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly
5. Submit a pull request

## 📄 License

This project is licensed under the MIT License - see the LICENSE file for details.

## 🙏 Acknowledgments

- [meehow/privtracker](https://github.com/meehow/privtracker) - BitTorrent tracker
- [libtorrent](https://libtorrent.org/) - BitTorrent library
- [Ollama](https://ollama.ai/) - Local LLM runtime

## 📞 Support

For issues and questions:
- Create an issue on GitHub
- Check the troubleshooting section
- Review the logs for error messages