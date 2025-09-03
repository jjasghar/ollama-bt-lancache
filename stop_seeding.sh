#!/bin/bash

# Ollama BitTorrent Lancache Seeding Shutdown Script
# This script stops all seeding processes while keeping the web server and tracker running

set -e

echo "🌱 Stopping Ollama BitTorrent Lancache Seeding..."

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

# Function to check if a service is running
check_service() {
    local pattern=$1
    local service_name=$2
    
    if pgrep -f "$pattern" >/dev/null 2>&1; then
        echo "✅ $service_name is running"
        return 0
    else
        echo "❌ $service_name is not running"
        return 1
    fi
}

# Check if web server and tracker are running
echo "🔍 Checking system services..."
web_server_running=false
tracker_running=false

if check_service "ollama-bt-lancache" "Web Server"; then
    web_server_running=true
fi

if check_service "privtracker" "BitTorrent Tracker"; then
    tracker_running=true
fi

# Stop auto seeder first (it manages other seeders)
echo "🤖 Stopping Auto Seeder..."
kill_processes "auto_seeder.py" "Auto Seeder"

# Stop individual seeder processes
echo "🌱 Stopping individual seeders..."
kill_processes "seeder.py" "Seeder"

# Stop client processes (they might be seeding too)
echo "📥 Stopping client processes..."
kill_processes "client.py" "Client"

# Wait a moment for all processes to fully terminate
sleep 2

# Final check for any remaining seeding processes
echo "🔍 Final check for remaining seeding processes..."

remaining_seeding=$(pgrep -f "auto_seeder|seeder\.py|client\.py" 2>/dev/null || true)

if [ -n "$remaining_seeding" ]; then
    echo "⚠️  Some seeding processes are still running: $remaining_seeding"
    echo "🛑 Force killing remaining seeding processes..."
    kill -KILL $remaining_seeding 2>/dev/null || true
    sleep 1
else
    echo "✅ All seeding processes stopped successfully"
fi

echo ""
echo "🎉 Seeding Stopped Successfully!"
echo ""
echo "📊 System Status:"
if [ "$web_server_running" = true ]; then
    echo "   🌐 Web Server: Running"
else
    echo "   🌐 Web Server: Stopped"
fi

if [ "$tracker_running" = true ]; then
    echo "   📡 BitTorrent Tracker: Running"
else
    echo "   📡 BitTorrent Tracker: Stopped"
fi

echo "   🤖 Auto Seeder: Stopped"
echo "   🌱 Individual Seeders: Stopped"
echo "   📥 Client Processes: Stopped"
echo ""

if [ "$web_server_running" = false ] || [ "$tracker_running" = false ]; then
    echo "⚠️  Some system services are not running"
    echo "🚀 To start the complete system:"
    echo "   ./start_system.sh"
    echo ""
fi

echo "🌱 To restart seeding:"
echo "   ./start_seeding.sh"
echo ""
echo "🛑 To stop everything:"
echo "   ./stop_system.sh"
