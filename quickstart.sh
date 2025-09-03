#!/bin/bash
# Quick Start Script for Ollama BitTorrent Lancache

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

print_status() {
    echo -e "${GREEN}🚀 $1${NC}"
}

print_info() {
    echo -e "${CYAN}$1${NC}"
}

print_warning() {
    echo -e "${YELLOW}$1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

# Check if running as root
if [[ $EUID -eq 0 ]]; then
   print_error "This script should not be run as root"
   exit 1
fi

# Check dependencies
check_dependencies() {
    print_info "Checking dependencies..."
    
    # Check Go
    if ! command -v go &> /dev/null; then
        print_error "Go not found. Please install Go 1.21+"
        exit 1
    fi
    
    # Check Python
    if ! command -v python3 &> /dev/null; then
        print_error "Python 3 not found. Please install Python 3.8+"
        exit 1
    fi
    
    # Check Git
    if ! command -v git &> /dev/null; then
        print_error "Git not found. Please install Git"
        exit 1
    fi
    
    print_success "All dependencies found"
}

# Setup tracker
setup_tracker() {
    print_info "Setting up BitTorrent tracker..."
    
    if [ ! -f tracker/tracker ]; then
        if [ ! -d tracker/privtracker ]; then
            print_info "Cloning privtracker repository..."
            cd tracker && git clone https://github.com/meehow/privtracker.git
        fi
        
        print_info "Building tracker..."
        cd privtracker && go build -o tracker
        cp tracker ../
        cd ../..
        print_success "Tracker built successfully"
    else
        print_info "Tracker already exists"
    fi
}

# Build server
build_server() {
    print_info "Building Go server..."
    cd server && go mod download && go build -o ollama-bt-lancache
    cd ..
    print_success "Server built successfully"
}

# Start services
start_services() {
    print_info "Starting services..."
    
    # Start tracker in background
    print_info "Starting BitTorrent tracker on port 8080..."
    cd tracker && ./tracker > tracker.log 2>&1 &
    TRACKER_PID=$!
    cd ..
    
    # Wait a moment for tracker to start
    sleep 2
    
    # Start server in background
    print_info "Starting main server on port 8081..."
    cd server && ./ollama-bt-lancache --port 8081 > server.log 2>&1 &
    SERVER_PID=$!
    cd ..
    
    # Wait a moment for server to start
    sleep 2
    
    print_success "Services started!"
    print_info "Tracker PID: $TRACKER_PID (port 8080)"
    print_info "Server PID: $SERVER_PID (port 8081)"
    print_info "Tracker log: tracker/tracker.log"
    print_info "Server log: server/server.log"
    
    # Save PIDs for cleanup
    echo $TRACKER_PID > .tracker.pid
    echo $SERVER_PID > .server.pid
    
    print_info "Web interface available at: http://localhost:8081"
    print_info "Press Ctrl+C to stop all services"
    
    # Wait for interrupt
    trap cleanup EXIT
    wait
}

# Cleanup function
cleanup() {
    print_info "Shutting down services..."
    
    if [ -f .tracker.pid ]; then
        TRACKER_PID=$(cat .tracker.pid)
        kill $TRACKER_PID 2>/dev/null || true
        rm -f .tracker.pid
    fi
    
    if [ -f .server.pid ]; then
        SERVER_PID=$(cat .server.pid)
        kill $SERVER_PID 2>/dev/null || true
        rm -f .server.pid
    fi
    
    print_success "Services stopped"
    exit 0
}

# Main function
main() {
    print_status "Ollama BitTorrent Lancache Quick Start"
    print_info "This script will set up and start all services"
    
    check_dependencies
    setup_tracker
    build_server
    start_services
}

# Run main function
main "$@"
