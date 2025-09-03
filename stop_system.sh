#!/bin/bash

# Ollama BitTorrent Lancache System Shutdown Script
# This script stops all components of the system

set -e

# Parse command line arguments
CLEAN_TORRENTS=false
for arg in "$@"; do
    case $arg in
        --clean)
            CLEAN_TORRENTS=true
            shift
            ;;
        -h|--help)
            echo "Usage: $0 [--clean]"
            echo ""
            echo "Options:"
            echo "  --clean    Also remove torrent files from ~/.ollama/models/"
            echo "  -h, --help Show this help message"
            exit 0
            ;;
        *)
            echo "Unknown option: $arg"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

echo "🛑 Stopping Ollama BitTorrent Lancache System..."
if [ "$CLEAN_TORRENTS" = true ]; then
    echo "🧹 Will also clean up torrent files"
fi

# Function to kill processes by name pattern
kill_processes() {
    local pattern=$1
    local description=$2
    
    echo "🔍 Looking for $description processes..."
    
    # Find PIDs of processes matching the pattern
    local pids=$(pgrep -f "$pattern" 2>/dev/null || true)
    
    if [ -n "$pids" ]; then
        echo "📊 Found $description processes: $pids"
        echo "🛑 Stopping $description processes..."
        
        # Try graceful termination first
        kill -TERM $pids 2>/dev/null || true
        
        # Wait a moment for graceful shutdown
        sleep 3
        
        # Check if processes are still running
        local remaining_pids=$(pgrep -f "$pattern" 2>/dev/null || true)
        
        if [ -n "$remaining_pids" ]; then
            echo "⚠️  Some processes still running, forcing termination..."
            kill -KILL $remaining_pids 2>/dev/null || true
        fi
        
        echo "✅ $description processes stopped"
    else
        echo "ℹ️  No $description processes found"
    fi
}

# Function to check if a port is in use
check_port() {
    local port=$1
    if lsof -Pi :$port -sTCP:LISTEN -t >/dev/null 2>&1; then
        return 0  # Port is in use
    else
        return 1  # Port is free
    fi
}

# Stop auto seeder first (it manages other seeders)
echo "🤖 Stopping Auto Seeder..."
kill_processes "auto_seeder.py" "Auto Seeder"

# Stop individual seeder processes
echo "🌱 Stopping individual seeders..."
kill_processes "seeder.py" "Seeder"

# Stop client processes
echo "📥 Stopping client processes..."
kill_processes "client.py" "Client"

# Stop web server
echo "🌐 Stopping Web Server..."
kill_processes "ollama-bt-lancache" "Web Server"

# Stop BitTorrent tracker
echo "📡 Stopping BitTorrent Tracker..."
kill_processes "privtracker" "BitTorrent Tracker"

# Wait a moment for all processes to fully terminate
sleep 2

# Check if ports are still in use
echo "🔍 Checking if ports are free..."

if check_port 8080; then
    echo "⚠️  Port 8080 (Web Server) is still in use"
    web_pid=$(lsof -ti :8080)
    if [ -n "$web_pid" ]; then
        echo "🛑 Force killing process on port 8080: $web_pid"
        kill -KILL $web_pid 2>/dev/null || true
    fi
else
    echo "✅ Port 8080 (Web Server) is free"
fi

if check_port 8081; then
    echo "⚠️  Port 8081 (Tracker) is still in use"
    tracker_pid=$(lsof -ti :8081)
    if [ -n "$tracker_pid" ]; then
        echo "🛑 Force killing process on port 8081: $tracker_pid"
        kill -KILL $tracker_pid 2>/dev/null || true
    fi
else
    echo "✅ Port 8081 (Tracker) is free"
fi

# Final check for any remaining processes
echo "🔍 Final check for remaining processes..."

remaining_processes=$(pgrep -f "ollama-bt-lancache|privtracker|auto_seeder|seeder\.py|client\.py" 2>/dev/null || true)

if [ -n "$remaining_processes" ]; then
    echo "⚠️  Some processes are still running: $remaining_processes"
    echo "🛑 Force killing remaining processes..."
    kill -KILL $remaining_processes 2>/dev/null || true
    sleep 1
else
    echo "✅ All processes stopped successfully"
fi

# Verify all ports are free
echo "🔍 Verifying all ports are free..."

if check_port 8080 && check_port 8081; then
    echo "⚠️  Some ports are still in use"
    echo "📊 Port status:"
    lsof -i :8080 -i :8081 2>/dev/null || echo "No processes found on ports 8080/8081"
else
    echo "✅ All ports are free"
fi

# Clean up torrent files if requested
if [ "$CLEAN_TORRENTS" = true ]; then
    echo ""
    echo "🧹 Cleaning up torrent files..."
    
    # Get the models directory
    MODELS_DIR="$HOME/.ollama/models"
    
    if [ -d "$MODELS_DIR" ]; then
        # Count torrent files
        TORRENT_COUNT=$(find "$MODELS_DIR" -name "*.torrent" -type f | wc -l)
        
        if [ "$TORRENT_COUNT" -gt 0 ]; then
            echo "📁 Found $TORRENT_COUNT torrent files in $MODELS_DIR"
            echo "🗑️  Removing torrent files..."
            
            # Remove torrent files
            find "$MODELS_DIR" -name "*.torrent" -type f -delete
            
            echo "✅ Removed $TORRENT_COUNT torrent files"
        else
            echo "ℹ️  No torrent files found to clean up"
        fi
    else
        echo "⚠️  Models directory not found: $MODELS_DIR"
    fi
fi

echo ""
echo "🎉 Ollama BitTorrent Lancache System Stopped Successfully!"
echo ""
echo "📊 System Status:"
echo "   🌐 Web Server: Stopped"
echo "   📡 BitTorrent Tracker: Stopped"
echo "   🤖 Auto Seeder: Stopped"
echo "   🌱 Individual Seeders: Stopped"
echo "   📥 Client Processes: Stopped"

if [ "$CLEAN_TORRENTS" = true ]; then
    echo "   🧹 Torrent Files: Cleaned up"
else
    echo "   📄 Torrent Files: Preserved"
fi

echo ""
echo "🚀 To restart the system:"
echo "   ./start_system.sh"
echo ""
echo "🌱 To start just seeding:"
echo "   ./start_seeding.sh"
