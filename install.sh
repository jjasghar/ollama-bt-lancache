#!/bin/bash
# Ollama BitTorrent Lancache Installer for Linux/macOS

set -e

# Default values
MODEL=""
SERVER_URL=""
TEST_MODE=false
CLEAN_MODE=false
SHOW_MODELS=false

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

# Function to show usage
show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo
    echo "Options:"
    echo "  --model MODEL     Download specific model (e.g., granite3.3:8b)"
    echo "  --server URL      Server URL (default: http://localhost:8080)"
    echo "  --test            Download to current directory instead of ~/.ollama/models"
    echo "  --clean           Remove virtual environment and exit"
    echo "  --list            List available models from server"
    echo "  -h, --help        Show this help message"
    echo
    echo "Examples:"
    echo "  $0 --list                                    # List available models"
    echo "  $0 --model granite3.3:8b                    # Download specific model"
    echo "  $0 --model phi3:mini --server http://192.168.1.100:8080  # Download from specific server"
    echo "  $0 --test --model granite3.3:8b             # Download to current directory"
    echo "  $0 --clean                                   # Remove virtual environment"
    echo
    echo "One-liner examples:"
    echo "  curl -sSL \"http://192.168.1.100:8080/install.sh\" | bash -s -- --model granite3.3:8b"
    echo "  curl -sSL \"http://192.168.1.100:8080/install.sh\" | bash -s -- --list"
}

# Function to parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --model)
                MODEL="$2"
                shift 2
                ;;
            --server)
                SERVER_URL="$2"
                shift 2
                ;;
            --test)
                TEST_MODE=true
                shift
                ;;
            --clean)
                CLEAN_MODE=true
                shift
                ;;
            --list)
                SHOW_MODELS=true
                shift
                ;;
            -h|--help)
                show_usage
                exit 0
                ;;
            *)
                print_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
    
    # Set defaults if not provided
    if [ -z "$SERVER_URL" ]; then
        SERVER_URL="http://localhost:8080"
    fi
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
            sudo apt-get install -y python3-venv python3-pip curl
        elif command_exists yum; then
            print_info "Installing system dependencies (CentOS/RHEL)..."
            sudo yum install -y python3 python3-pip python3-venv curl
        elif command_exists dnf; then
            print_info "Installing system dependencies (Fedora)..."
            sudo dnf install -y python3 python3-pip python3-venv curl
        else
            print_warning "Could not detect package manager. Please install Python 3.8+ and curl manually."
        fi
    elif [[ "$os" == "macos" ]]; then
        if command_exists brew; then
            print_info "Installing system dependencies (macOS with Homebrew)..."
            brew install python3 curl
        else
            print_warning "Homebrew not found. Please install Python 3.8+ and curl manually."
        fi
    fi
}

# Function to list available models
list_models() {
    print_info "Fetching available models from $SERVER_URL..."
    
    if ! command_exists curl; then
        print_error "curl is required to fetch model list"
        print_info "Attempting to install curl..."
        install_python_deps
        if ! command_exists curl; then
            print_error "Failed to install curl. Please install it manually."
            exit 1
        fi
    fi
    
    # Fetch models from server
    MODELS_JSON=$(curl -s "$SERVER_URL/api/models" 2>/dev/null)
    
    if [ $? -ne 0 ] || [ -z "$MODELS_JSON" ]; then
        print_error "Failed to fetch models from server: $SERVER_URL"
        print_info "Make sure the server is running and accessible"
        exit 1
    fi
    
    # Parse and display models
    echo
    print_success "Available Models:"
    echo "----------------------------------------"
    
    echo "$MODELS_JSON" | python3 -c "
import sys, json
try:
    models = json.load(sys.stdin)
    if not models:
        print('No models available on server')
    else:
        for model in models:
            size_mb = model['size'] / (1024 * 1024)
            print(f'📁 {model[\"name\"]:<25} {size_mb:>8.1f} MB')
except Exception as e:
    print(f'Error parsing models: {e}')
    sys.exit(1)
"
    
    echo "----------------------------------------"
    echo
    print_info "To download a model, use:"
    print_info "  $0 --model <model-name>"
    print_info "  curl -sSL \"$SERVER_URL/install.sh\" | bash -- --model <model-name>"
}

# Function to clean virtual environment
clean_venv() {
    VENV_PATH="$HOME/.ollama-bt-venv"
    
    if [ -d "$VENV_PATH" ]; then
        print_info "Removing virtual environment at $VENV_PATH..."
        rm -rf "$VENV_PATH"
        print_success "Virtual environment removed"
    else
        print_info "No virtual environment found at $VENV_PATH"
    fi
    
    # Also remove seeder script if it exists
    SEEDER_PATH="$HOME/seeder.py"
    if [ -f "$SEEDER_PATH" ]; then
        print_info "Removing seeder script at $SEEDER_PATH..."
        rm -f "$SEEDER_PATH"
        print_success "Seeder script removed"
    fi
}

# Function to setup virtual environment
setup_venv() {
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
}

# Function to download client script
download_client() {
    CLIENT_URL="$SERVER_URL/client.py"
    CLIENT_PATH="$HOME/client.py"
    print_info "Downloading client script..."
    
    if curl -sSL "$CLIENT_URL" -o "$CLIENT_PATH"; then
        print_success "Downloaded client script to: $CLIENT_PATH"
        chmod +x "$CLIENT_PATH"
    else
        print_error "Failed to download client script"
        exit 1
    fi
}

# Function to download model
download_model() {
    if [ -z "$MODEL" ]; then
        print_error "No model specified. Use --list to see available models or --model <name> to download"
        exit 1
    fi
    
    # Determine output directory
    if [ "$TEST_MODE" = true ]; then
        OUTPUT_DIR="$(pwd)/downloads"
        print_info "Test mode: downloading to $OUTPUT_DIR"
    else
        OUTPUT_DIR="$HOME/.ollama/models"
        print_info "Downloading to Ollama directory: $OUTPUT_DIR"
    fi
    
    # Create output directory
    mkdir -p "$OUTPUT_DIR"
    
    # Download model using client script
    print_status "Starting model download..."
    print_info "Model: $MODEL"
    print_info "Server: $SERVER_URL"
    print_info "Output: $OUTPUT_DIR"
    
    CLIENT_PATH="$HOME/client.py"
    if [ ! -f "$CLIENT_PATH" ]; then
        print_error "Client script not found. Please run setup first."
        exit 1
    fi
    
    # Activate virtual environment
    source "$HOME/.ollama-bt-venv/bin/activate"
    
    # Download the model
    python3 "$CLIENT_PATH" --server "$SERVER_URL" --model "$MODEL" --output "$OUTPUT_DIR"
    
    if [ $? -eq 0 ]; then
        print_success "Model download complete!"
        print_info "Model downloaded to: $OUTPUT_DIR"
        
        if [ "$TEST_MODE" = false ]; then
            echo
            print_info "📋 Next steps:"
            echo -e "${WHITE}1. Install Ollama from https://ollama.ai if not already installed${NC}"
            echo -e "${WHITE}2. Use 'ollama run $MODEL' to start using your model${NC}"
        fi
    else
        print_error "Model download failed"
        exit 1
    fi
}

# Main function
main() {
    parse_args "$@"
    
    # Handle special modes
    if [ "$CLEAN_MODE" = true ]; then
        clean_venv
        exit 0
    fi
    
    if [ "$SHOW_MODELS" = true ]; then
        list_models
        exit 0
    fi
    
    # If no model specified, show available models
    if [ -z "$MODEL" ]; then
        print_warning "No model specified. Showing available models..."
        list_models
        exit 0
    fi
    
    # Setup environment and download model
    print_status "Installing Ollama BitTorrent Lancache..."
    print_info "Server: $SERVER_URL"
    print_info "Model: $MODEL"
    
    setup_venv
    download_client
    download_model
}

# Run main function
main "$@"