#!/bin/bash

# Ollama BitTorrent Lancache System Startup Script
# This script starts the web server, tracker, and auto seeder

set -e

echo "🚀 Starting Ollama BitTorrent Lancache System..."

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Configuration
WEBSERVER_PORT=8080
TRACKER_PORT=8081

# Get local IP address (same logic as server)
get_local_ip() {
    # Try to get the IP address by connecting to a remote server
    local ip=$(python3 -c "
import socket
try:
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    s.connect(('8.8.8.8', 80))
    ip = s.getsockname()[0]
    s.close()
    print(ip)
except:
    print('localhost')
")
    echo "$ip"
}

LOCAL_IP=$(get_local_ip)
TRACKER_URL="http://$LOCAL_IP:$TRACKER_PORT"

echo "🌐 Detected local IP: $LOCAL_IP"

# Function to check if a port is in use
check_port() {
    local port=$1
    if lsof -Pi :$port -sTCP:LISTEN -t >/dev/null 2>&1; then
        echo "⚠️  Port $port is already in use"
        return 1
    fi
    return 0
}

# Function to wait for a service to be ready
wait_for_service() {
    local url=$1
    local service_name=$2
    local max_attempts=30
    local attempt=1
    
    echo "⏳ Waiting for $service_name to be ready..."
    echo "   Checking: $url"
    
    while [ $attempt -le $max_attempts ]; do
        if curl -s --connect-timeout 5 "$url" >/dev/null 2>&1; then
            echo "✅ $service_name is ready"
            return 0
        fi
        
        echo "   Attempt $attempt/$max_attempts - waiting..."
        sleep 2
        attempt=$((attempt + 1))
    done
    
    echo "❌ $service_name failed to start within timeout"
    echo "   Last attempted URL: $url"
    return 1
}

# Check if ports are available
echo "🔍 Checking port availability..."
if ! check_port $WEBSERVER_PORT; then
    echo "❌ Web server port $WEBSERVER_PORT is already in use"
    exit 1
fi

if ! check_port $TRACKER_PORT; then
    echo "❌ Tracker port $TRACKER_PORT is already in use"
    exit 1
fi

# Start the BitTorrent tracker
echo "📡 Starting BitTorrent tracker on port $TRACKER_PORT..."
osascript -e "tell application \"Terminal\" to do script \"cd '$SCRIPT_DIR' && echo '📡 Starting BitTorrent Tracker...' && cd tracker/privtracker && PORT=$TRACKER_PORT ./tracker\""

# Give the tracker a moment to start
sleep 3

# Wait for tracker to be ready
if ! wait_for_service "http://$LOCAL_IP:$TRACKER_PORT" "BitTorrent Tracker"; then
    echo "❌ Failed to start tracker"
    exit 1
fi

# Start the web server
echo "🌐 Starting web server on port $WEBSERVER_PORT..."
osascript -e "tell application \"Terminal\" to do script \"cd '$SCRIPT_DIR' && echo '🌐 Starting Web Server...' && cd server && ./ollama-bt-lancache\""

# Wait for web server to be ready
if ! wait_for_service "http://$LOCAL_IP:$WEBSERVER_PORT/api/models" "Web Server"; then
    echo "❌ Failed to start web server"
    exit 1
fi

# Start the auto seeder
echo "🤖 Starting auto seeder..."
osascript -e "tell application \"Terminal\" to do script \"cd '$SCRIPT_DIR' && echo '🤖 Starting Auto Seeder...' && python3 auto_seeder.py --tracker $TRACKER_URL --start-existing-only\""

echo ""
echo "🎉 Ollama BitTorrent Lancache System Started Successfully!"
echo ""
echo "📊 Services:"
echo "   🌐 Web Server: http://$LOCAL_IP:$WEBSERVER_PORT"
echo "   📡 BitTorrent Tracker: http://$LOCAL_IP:$TRACKER_PORT"
echo "   🤖 Auto Seeder: Monitoring and seeding all torrents"
echo ""
echo "📋 Available Models:"
curl -s "http://$LOCAL_IP:$WEBSERVER_PORT/api/models" | python3 -c "
import sys, json
try:
    models = json.load(sys.stdin)
    for model in models:
        size_mb = model['size'] / (1024 * 1024)
        print(f'   📁 {model[\"name\"]} ({size_mb:.1f} MB)')
except:
    print('   ⚠️  Could not fetch model list')
"
echo ""
echo "🛑 To stop the system, close all terminal windows or press Ctrl+C in each terminal"
echo "📖 For more information, visit: http://$LOCAL_IP:$WEBSERVER_PORT"

