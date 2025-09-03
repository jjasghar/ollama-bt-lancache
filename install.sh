#!/bin/bash
# Ollama BitTorrent Lancache Installer for Linux/macOS

set -e

# Default values
MODEL=${1:-"all"}
SERVER_URL=${2:-"http://localhost:8080"}

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m' # No Color

# Function to print colored output
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

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to detect OS
detect_os() {
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        echo "linux"
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        echo "macos"
    else
        echo "unknown"
    fi
}

# Function to install Python dependencies based on OS
install_python_deps() {
    local os=$(detect_os)
    
    if [[ "$os" == "linux" ]]; then
        if command_exists apt-get; then
            print_info "Installing system dependencies (Ubuntu/Debian)..."
            sudo apt-get update
            sudo apt-get install -y python3-venv python3-pip
        elif command_exists yum; then
            print_info "Installing system dependencies (CentOS/RHEL)..."
            sudo yum install -y python3 python3-pip python3-venv
        elif command_exists dnf; then
            print_info "Installing system dependencies (Fedora)..."
            sudo dnf install -y python3 python3-pip python3-venv
        else
            print_warning "Could not detect package manager. Please install Python 3.8+ manually."
        fi
    elif [[ "$os" == "macos" ]]; then
        if command_exists brew; then
            print_info "Installing system dependencies (macOS with Homebrew)..."
            brew install python3
        else
            print_warning "Homebrew not found. Please install Python 3.8+ manually from https://python.org"
        fi
    fi
}

# Main installation function
main() {
    print_status "Installing Ollama BitTorrent Lancache..."
    print_info "Server: $SERVER_URL"
    print_info "Model: $MODEL"
    
    # Check if Python is installed
    if ! command_exists python3; then
        print_error "Python 3 not found"
        print_info "Attempting to install Python dependencies..."
        install_python_deps
        
        if ! command_exists python3; then
            print_error "Python 3 installation failed. Please install Python 3.8+ manually."
            exit 1
        fi
    fi
    
    # Check Python version
    PYTHON_VERSION=$(python3 --version 2>&1)
    print_success "Python found: $PYTHON_VERSION"
    
    # Extract version numbers
    if [[ $PYTHON_VERSION =~ Python[[:space:]]([0-9]+)\.([0-9]+) ]]; then
        MAJOR=${BASH_REMATCH[1]}
        MINOR=${BASH_REMATCH[2]}
        
        if [ "$MAJOR" -lt 3 ] || ([ "$MAJOR" -eq 3 ] && [ "$MINOR" -lt 8 ]); then
            print_error "Python 3.8+ required. Found: $MAJOR.$MINOR"
            exit 1
        fi
    fi
    
    # Create virtual environment
    VENV_PATH="$HOME/.ollama-bt-venv"
    if [ -d "$VENV_PATH" ]; then
        print_warning "Virtual environment already exists at $VENV_PATH"
        print_info "Removing existing environment..."
        rm -rf "$VENV_PATH"
    fi
    
    print_info "Creating virtual environment..."
    python3 -m venv "$VENV_PATH"
    
    # Activate virtual environment
    print_info "Activating virtual environment..."
    source "$VENV_PATH/bin/activate"
    
    # Install required packages
    print_info "Installing required packages..."
    pip install --upgrade pip
    pip install libtorrent requests
    
    # Download seeder script
    SEEDER_URL="$SERVER_URL/seeder.py"
    SEEDER_PATH="$HOME/seeder.py"
    print_info "Downloading seeder script..."
    
    if curl -sSL "$SEEDER_URL" -o "$SEEDER_PATH"; then
        print_success "Downloaded seeder script to: $SEEDER_PATH"
        chmod +x "$SEEDER_PATH"
    else
        print_error "Failed to download seeder script"
        exit 1
    fi
    
    # Create Ollama models directory if it doesn't exist
    OLLAMA_DIR="$HOME/.ollama/models"
    if [ ! -d "$OLLAMA_DIR" ]; then
        print_info "Creating Ollama models directory..."
        mkdir -p "$OLLAMA_DIR"
    fi
    
    # Download models based on parameter
    print_status "Starting model download..."
    
    if [ "$MODEL" = "all" ]; then
        print_info "Downloading all available models..."
        python3 "$SEEDER_PATH" --server "$SERVER_URL" --download-all
    else
        print_info "Downloading model: $MODEL"
        python3 "$SEEDER_PATH" --server "$SERVER_URL" --model "$MODEL"
    fi
    
    if [ $? -eq 0 ]; then
        print_success "Installation complete!"
        print_info "Models downloaded to: $OLLAMA_DIR"
        
        echo
        print_info "📋 Next steps:"
        echo -e "${WHITE}1. Install Ollama from https://ollama.ai if not already installed${NC}"
        echo -e "${WHITE}2. Use 'ollama run <model-name>' to start using your models${NC}"
        echo -e "${WHITE}3. To seed models for other clients, run: python3 $SEEDER_PATH --seed <model-path>${NC}"
    else
        print_error "Installation failed"
        exit 1
    fi
}

# Function to show usage
show_usage() {
    echo "Usage: $0 [MODEL] [SERVER_URL]"
    echo
    echo "Arguments:"
    echo "  MODEL       Model name to download (default: all)"
    echo "  SERVER_URL  Server URL (default: http://localhost:8080)"
    echo
    echo "Examples:"
    echo "  $0                                    # Download all models from localhost:8080"
    echo "  $0 llama2:7b                         # Download specific model from localhost:8080"
    echo "  $0 all http://192.168.1.100:8080    # Download all models from specific server"
    echo "  $0 llama2:7b http://192.168.1.100:8080  # Download specific model from specific server"
}

# Check if help is requested
if [[ "$1" == "-h" || "$1" == "--help" ]]; then
    show_usage
    exit 0
fi

# Run main function
main "$@"
