# Auto Seeder for Ollama BitTorrent Lancache

The Auto Seeder automatically monitors the `~/.ollama/models` directory for torrent files and starts seeding each one in a separate terminal window.

## Features

- **Automatic Detection**: Monitors for new torrent files created by the web server
- **Terminal Management**: Starts each seeder in its own terminal window
- **Process Monitoring**: Tracks and manages seeder processes
- **Graceful Shutdown**: Properly stops all seeders when interrupted
- **Status Reporting**: Shows current seeding status and active seeders

## Usage

### Basic Usage

```bash
# Start monitoring and auto-seed all torrents
python3 auto_seeder.py --tracker http://localhost:8081

# Start seeders for existing torrents only (no monitoring)
python3 auto_seeder.py --tracker http://localhost:8081 --start-existing-only

# Check current status
python3 auto_seeder.py --tracker http://localhost:8081 --status
```

### Advanced Usage

```bash
# Custom models directory
python3 auto_seeder.py --models-dir ~/.ollama/models --tracker http://localhost:8081

# Custom check interval (default: 10 seconds)
python3 auto_seeder.py --tracker http://localhost:8081 --check-interval 5

# Start existing seeders and monitor for new ones
python3 auto_seeder.py --tracker http://localhost:8081
```

## Command Line Options

- `--models-dir`: Models directory to monitor (default: `~/.ollama/models`)
- `--tracker`: BitTorrent tracker URL (required)
- `--check-interval`: Check interval in seconds (default: 10)
- `--start-existing-only`: Start seeders for existing torrents only, don't monitor
- `--status`: Show current status and exit

## How It Works

1. **Discovery**: Scans the models directory for `*.torrent` files
2. **Seeding**: Starts a seeder process in a new terminal for each torrent
3. **Monitoring**: Continuously checks for new torrent files
4. **Management**: Tracks running seeders and handles process lifecycle

## Integration with Web Server

The Auto Seeder works seamlessly with the web server:

1. **Web Server** creates torrent files for each model
2. **Auto Seeder** detects new torrent files and starts seeding
3. **Clients** can download from multiple seeds for faster distribution

## Example Workflow

```bash
# 1. Start the system
./start_system.sh

# 2. Auto seeder will automatically start seeding all existing models:
#    - phi3:mini
#    - granite3.3:8b
#    - granite-code:8b
#    - granite3.3:latest

# 3. When you add a new model to ~/.ollama/models:
#    - Web server creates a new torrent file
#    - Auto seeder detects it and starts seeding
#    - New model is immediately available for distribution
```

## Terminal Windows

The Auto Seeder creates separate terminal windows for each seeder:

- **Terminal 1**: Web Server
- **Terminal 2**: BitTorrent Tracker  
- **Terminal 3**: Auto Seeder (monitoring)
- **Terminal 4**: Seeder for phi3:mini
- **Terminal 5**: Seeder for granite3.3:8b
- **Terminal 6**: Seeder for granite-code:8b
- **Terminal 7**: Seeder for granite3.3:latest

## Status Monitoring

The Auto Seeder provides real-time status information:

```
📊 Auto Seeder Status:
📁 Monitoring directory: /Users/jjasghar/.ollama/models
📡 Tracker URL: http://localhost:8081
⏱️  Check interval: 10 seconds
🔍 Monitored torrents: 4
🌱 Active seeders: 4

🌱 Active Seeders:
   📄 phi3:mini
   📄 granite3.3:8b
   📄 granite-code:8b
   📄 granite3.3:latest
```

## Stopping the System

To stop all seeders:

1. **Ctrl+C** in the Auto Seeder terminal (stops monitoring and all seeders)
2. **Close individual terminal windows** (stops specific seeders)
3. **Use the start_system.sh script** (manages the entire system)

## Troubleshooting

### No Torrent Files Found
- Ensure the web server is running and has created torrent files
- Check that models exist in `~/.ollama/models`
- Verify the models directory path is correct

### Seeders Not Starting
- Check that the virtual environment is activated
- Verify the seeder.py script is executable
- Ensure the tracker is running and accessible

### High CPU Usage
- Increase the check interval with `--check-interval 30`
- Monitor system resources and adjust accordingly

## Integration with start_system.sh

The `start_system.sh` script automatically starts the Auto Seeder as part of the complete system:

```bash
./start_system.sh
```

This will start:
1. BitTorrent Tracker
2. Web Server  
3. Auto Seeder (with all existing torrents)

## Benefits

- **Automatic Scaling**: New models are immediately available for seeding
- **Resource Management**: Each seeder runs in its own process
- **Fault Tolerance**: Individual seeders can be restarted independently
- **Easy Monitoring**: Clear status reporting and process management
- **Seamless Integration**: Works automatically with the web server

