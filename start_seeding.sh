#!/bin/bash

# Ollama BitTorrent Lancache Seeding Startup Script
# This script starts seeding processes for existing torrents

set -e

echo "🌱 Starting Ollama BitTorrent Lancache Seeding..."

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Configuration
TRACKER_URL="http://localhost:8081"
WEBSERVER_URL="http://localhost:8080"

# Function to check if a service is running
check_service() {
    local url=$1
    local service_name=$2
    local max_attempts=5
    local attempt=1
    
    echo "🔍 Checking if $service_name is running..."
    
    while [ $attempt -le $max_attempts ]; do
        if curl -s "$url" >/dev/null 2>&1; then
            echo "✅ $service_name is running"
            return 0
        fi
        
        echo "   Attempt $attempt/$max_attempts - waiting..."
        sleep 1
        attempt=$((attempt + 1))
    done
    
    echo "❌ $service_name is not running"
    return 1
}

# Function to check if seeding is already running
check_seeding_running() {
    seeding_processes=$(pgrep -f "auto_seeder|seeder\.py" 2>/dev/null || true)
    
    if [ -n "$seeding_processes" ]; then
        echo "⚠️  Seeding processes are already running:"
        ps aux | grep -E "(auto_seeder|seeder\.py)" | grep -v grep | while read line; do
            echo "   $line"
        done
        return 0
    else
        return 1
    fi
}

# Check if seeding is already running
if check_seeding_running; then
    echo ""
    echo "❓ Seeding processes are already running. What would you like to do?"
    echo "   1) Stop existing seeding and start fresh"
    echo "   2) Keep existing seeding running"
    echo "   3) Cancel"
    echo ""
    read -p "Enter your choice (1-3): " choice
    
    case $choice in
        1)
            echo "🛑 Stopping existing seeding processes..."
            ./stop_seeding.sh
            echo "✅ Existing seeding stopped"
            ;;
        2)
            echo "✅ Keeping existing seeding processes running"
            exit 0
            ;;
        3)
            echo "❌ Cancelled"
            exit 0
            ;;
        *)
            echo "❌ Invalid choice, cancelling"
            exit 1
            ;;
    esac
fi

# Check if required services are running
echo "🔍 Checking required services..."

tracker_running=false
webserver_running=false

if check_service "$TRACKER_URL" "BitTorrent Tracker"; then
    tracker_running=true
fi

if check_service "$WEBSERVER_URL/api/models" "Web Server"; then
    webserver_running=true
fi

# If services are not running, offer to start them
if [ "$tracker_running" = false ] || [ "$webserver_running" = false ]; then
    echo ""
    echo "⚠️  Required services are not running:"
    [ "$tracker_running" = false ] && echo "   ❌ BitTorrent Tracker"
    [ "$webserver_running" = false ] && echo "   ❌ Web Server"
    echo ""
    echo "❓ What would you like to do?"
    echo "   1) Start the complete system (recommended)"
    echo "   2) Start just the required services"
    echo "   3) Start seeding anyway (may not work properly)"
    echo "   4) Cancel"
    echo ""
    read -p "Enter your choice (1-4): " choice
    
    case $choice in
        1)
            echo "🚀 Starting complete system..."
            ./start_system.sh
            exit 0
            ;;
        2)
            echo "🚀 Starting required services..."
            
            if [ "$tracker_running" = false ]; then
                echo "📡 Starting BitTorrent Tracker..."
                osascript -e "tell application \"Terminal\" to do script \"cd '$SCRIPT_DIR' && echo '📡 Starting BitTorrent Tracker...' && cd tracker/privtracker && PORT=8081 go run .\""
                
                # Wait for tracker to be ready
                echo "⏳ Waiting for tracker to be ready..."
                sleep 5
            fi
            
            if [ "$webserver_running" = false ]; then
                echo "🌐 Starting Web Server..."
                osascript -e "tell application \"Terminal\" to do script \"cd '$SCRIPT_DIR' && echo '🌐 Starting Web Server...' && cd server && ./ollama-bt-lancache\""
                
                # Wait for web server to be ready
                echo "⏳ Waiting for web server to be ready..."
                sleep 5
            fi
            ;;
        3)
            echo "⚠️  Starting seeding anyway..."
            ;;
        4)
            echo "❌ Cancelled"
            exit 0
            ;;
        *)
            echo "❌ Invalid choice, cancelling"
            exit 1
            ;;
    esac
fi

# Check if virtual environment exists
if [ ! -d "venv" ]; then
    echo "❌ Virtual environment not found. Please run setup first:"
    echo "   python3 -m venv venv"
    echo "   source venv/bin/activate"
    echo "   pip install libtorrent requests"
    exit 1
fi

# Check if auto_seeder.py exists
if [ ! -f "auto_seeder.py" ]; then
    echo "❌ auto_seeder.py not found in current directory"
    exit 1
fi

# Start the auto seeder
echo "🤖 Starting Auto Seeder..."
osascript -e "tell application \"Terminal\" to do script \"cd '$SCRIPT_DIR' && echo '🤖 Starting Auto Seeder...' && python3 auto_seeder.py --tracker $TRACKER_URL --start-existing-only\""

# Wait a moment for the seeder to start
sleep 3

# Check if seeding started successfully
echo "🔍 Checking if seeding started successfully..."

seeding_processes=$(pgrep -f "auto_seeder|seeder\.py" 2>/dev/null || true)

if [ -n "$seeding_processes" ]; then
    echo "✅ Seeding started successfully!"
    echo ""
    echo "📊 Active Seeding Processes:"
    ps aux | grep -E "(auto_seeder|seeder\.py)" | grep -v grep | while read line; do
        echo "   $line"
    done
    
    # Count active seeders
    seeder_count=$(pgrep -f "seeder\.py" 2>/dev/null | wc -l)
    auto_seeder_count=$(pgrep -f "auto_seeder" 2>/dev/null | wc -l)
    
    echo ""
    echo "📊 Seeding Summary:"
    echo "   🤖 Auto Seeder processes: $auto_seeder_count"
    echo "   🌱 Individual Seeder processes: $seeder_count"
    
    # Show available models
    echo ""
    echo "📋 Available Models for Seeding:"
    if curl -s "$WEBSERVER_URL/api/models" >/dev/null 2>&1; then
        curl -s "$WEBSERVER_URL/api/models" | python3 -c "
import sys, json
try:
    models = json.load(sys.stdin)
    for model in models:
        size_mb = model['size'] / (1024 * 1024)
        print(f'   📁 {model[\"name\"]} ({size_mb:.1f} MB)')
except:
    print('   ⚠️  Could not fetch model list')
" 2>/dev/null || echo "   ⚠️  Could not fetch model list"
    else
        echo "   ⚠️  Web server not accessible"
    fi
    
else
    echo "❌ Failed to start seeding"
    echo "💡 Check the auto seeder terminal for error messages"
    exit 1
fi

echo ""
echo "🎉 Seeding Started Successfully!"
echo ""
echo "📊 System Status:"
echo "   🌐 Web Server: Running"
echo "   📡 BitTorrent Tracker: Running"
echo "   🤖 Auto Seeder: Running"
echo "   🌱 Individual Seeders: Running"
echo ""
echo "🛑 To stop seeding:"
echo "   ./stop_seeding.sh"
echo ""
echo "🛑 To stop everything:"
echo "   ./stop_system.sh"
echo ""
echo "📖 For more information:"
echo "   http://localhost:8080"
