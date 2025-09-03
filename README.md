# Ollama BitTorrent Lancache

A BitTorrent-based solution for distributing Ollama model blobs across multiple machines, providing horizontal scaling instead of point-to-point connections.

## Architecture

This project consists of two main services:

1. **Server Application** - Main application that serves the web interface and manages model discovery
2. **BitTorrent Tracker** - Private tracker service for coordinating peer connections

## Features

- **Dynamic Model Discovery**: Automatically detects models in `~/.ollama/models` directory
- **BitTorrent Transfer**: Uses BitTorrent protocol for efficient, scalable distribution
- **Cross-Platform Support**: PowerShell (Windows) and Bash (Linux/macOS) client scripts
- **Python-Based Clients**: Lightweight Python BitTorrent clients for blob downloads
- **Local IP Detection**: Automatically detects and uses internal network IP addresses
- **Web Interface**: User-friendly interface for managing and downloading models

## Components

### Server Application
- Go-based web server
- Model discovery and torrent file generation
- Web interface for model management
- Dynamic torrent creation based on local network configuration

### BitTorrent Tracker
- Private tracker service using [privtracker](https://github.com/meehow/privtracker)
- Coordinates peer connections for efficient file sharing
- Handles multiple concurrent downloads

### Client Scripts
- **PowerShell (Windows)**: `install.ps1` - Sets up Python environment and downloads models
- **Bash (Linux/macOS)**: `install.sh` - Sets up Python environment and downloads models
- **Python Seeder**: `seeder.py` - Standalone script for seeding models (useful for testing)

## Quick Start

### 1. Start the Services

```bash
# Start the BitTorrent tracker
./tracker/tracker

# Start the main server application
./server/ollama-bt-lancache

# Start a seeder for a specific model (optional)
python3 seeder.py --model llama2:7b
```

### 2. Install on Client Machines

#### Windows (PowerShell)
```powershell
# Run as Administrator
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
Invoke-WebRequest -Uri "http://YOUR_SERVER_IP:8080/install.ps1" -OutFile "install.ps1"
.\install.ps1
```

#### Linux/macOS (Bash)
```bash
curl -sSL "http://YOUR_SERVER_IP:8080/install.sh" | bash
```

### 3. Download Models

- Use the web interface at `http://YOUR_SERVER_IP:8080`
- Or use the command line: `ollama-bt download llama2:7b`

## Configuration

The server automatically detects:
- Local network IP address
- Available models in `~/.ollama/models`
- Network configuration for optimal BitTorrent performance

## Requirements

- Go 1.21+ for the server application
- Python 3.8+ for client scripts
- BitTorrent tracker (privtracker)
- Network access between machines

## Development

### Building the Server
```bash
cd server
go build -o ollama-bt-lancache
```

### Running Tests
```bash
cd server
go test ./...
```

## License

MIT License - see LICENSE file for details.
