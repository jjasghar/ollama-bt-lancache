# BitTorrent Tracker

This directory contains the configuration and setup for the BitTorrent tracker service using [privtracker](https://github.com/meehow/privtracker).

## Setup

### 1. Install privtracker

```bash
# Clone the privtracker repository
git clone https://github.com/meehow/privtracker.git
cd privtracker

# Build the tracker
go build -o tracker

# Copy the binary to this directory
cp tracker ../tracker/
```

### 2. Configuration

The tracker runs on port 8080 by default. You can modify the configuration by editing the tracker binary or using environment variables.

### 3. Running the Tracker

```bash
# Start the tracker
./tracker

# Or with custom port
PORT=8080 ./tracker
```

## Integration

The main server application will automatically connect to the tracker at `http://localhost:8080` (or the configured URL).

## Features

- Private tracker for secure model distribution
- Handles multiple concurrent connections
- Efficient peer coordination
- Web interface for monitoring

## Security

This is a private tracker intended for internal network use only. Do not expose it to the public internet.
