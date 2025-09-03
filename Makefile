.PHONY: help build clean run-server run-tracker test install-deps setup-tracker

# Default target
help:
	@echo "Ollama BitTorrent Lancache - Available targets:"
	@echo ""
	@echo "  build          - Build the Go server application"
	@echo "  clean          - Clean build artifacts"
	@echo "  run-server     - Run the main server application"
	@echo "  run-tracker    - Run the BitTorrent tracker"
	@echo "  test           - Run tests"
	@echo "  install-deps   - Install Go dependencies"
	@echo "  setup-tracker  - Setup the BitTorrent tracker"
	@echo "  all            - Build and setup everything"
	@echo ""

# Build the Go server application
build:
	@echo "Building Go server application..."
	cd server && go build -o ollama-bt-lancache
	@echo "✅ Build complete: server/ollama-bt-lancache"

# Clean build artifacts
clean:
	@echo "Cleaning build artifacts..."
	rm -f server/ollama-bt-lancache
	@echo "✅ Clean complete"

# Install Go dependencies
install-deps:
	@echo "Installing Go dependencies..."
	cd server && go mod download
	@echo "✅ Dependencies installed"

# Setup the BitTorrent tracker
setup-tracker:
	@echo "Setting up BitTorrent tracker..."
	@if [ ! -f tracker/tracker ]; then \
		echo "Tracker binary not found. Please follow the setup instructions:"; \
		echo "1. git clone https://github.com/meehow/privtracker.git"; \
		echo "2. cd privtracker && go build -o tracker"; \
		echo "3. cp tracker ../tracker/"; \
		echo ""; \
		echo "Or run: make setup-tracker-auto"; \
		exit 1; \
	fi
	@echo "✅ Tracker setup complete"

# Auto-setup tracker (clones and builds)
setup-tracker-auto:
	@echo "Auto-setting up BitTorrent tracker..."
	@if [ ! -d tracker/privtracker ]; then \
		cd tracker && git clone https://github.com/meehow/privtracker.git; \
	fi
	@cd tracker/privtracker && go build -o tracker
	@cp tracker/privtracker/tracker tracker/
	@echo "✅ Tracker auto-setup complete"

# Run the main server application
run-server: build
	@echo "Starting Ollama BitTorrent Lancache server..."
	@echo "Server will be available at: http://localhost:8080"
	@echo "Press Ctrl+C to stop"
	cd server && ./ollama-bt-lancache

# Run the BitTorrent tracker
run-tracker: setup-tracker
	@echo "Starting BitTorrent tracker..."
	@echo "Tracker will be available at: http://localhost:8080"
	@echo "Press Ctrl+C to stop"
	cd tracker && ./tracker

# Run tests
test:
	@echo "Running tests..."
	cd server && go test ./...
	@echo "✅ Tests complete"

# Build and setup everything
all: install-deps build setup-tracker
	@echo "✅ All targets complete"

# Development helpers
dev-server: build
	@echo "Starting development server with auto-reload..."
	@echo "Note: Install 'air' for auto-reload: go install github.com/cosmtrek/air@latest"
	@if command -v air >/dev/null 2>&1; then \
		cd server && air; \
	else \
		echo "Air not found. Starting without auto-reload..."; \
		cd server && ./ollama-bt-lancache; \
	fi

# Docker helpers (if you want to containerize later)
docker-build:
	@echo "Building Docker image..."
	docker build -t ollama-bt-lancache .
	@echo "✅ Docker image built"

docker-run:
	@echo "Running Docker container..."
	docker run -p 8080:8080 -v ~/.ollama:/root/.ollama ollama-bt-lancache

# Utility targets
check-deps:
	@echo "Checking dependencies..."
	@command -v go >/dev/null 2>&1 || { echo "❌ Go not found. Please install Go 1.21+"; exit 1; }
	@command -v python3 >/dev/null 2>&1 || { echo "❌ Python3 not found. Please install Python 3.8+"; exit 1; }
	@echo "✅ All dependencies found"

lint:
	@echo "Running linter..."
	@if command -v golangci-lint >/dev/null 2>&1; then \
		cd server && golangci-lint run; \
	else \
		echo "golangci-lint not found. Install with: go install github.com/golangci/golangci-lint/cmd/golangci-lint@latest"; \
	fi

format:
	@echo "Formatting Go code..."
	cd server && go fmt ./...
	@echo "✅ Code formatted"

# Show project status
status:
	@echo "Project Status:"
	@echo "  Go server: $(shell if [ -f server/ollama-bt-lancache ]; then echo "✅ Built"; else echo "❌ Not built"; fi)"
	@echo "  Tracker: $(shell if [ -f tracker/tracker ]; then echo "✅ Ready"; else echo "❌ Not ready"; fi)"
	@echo "  Dependencies: $(shell if [ -d server/vendor ] || [ -f server/go.sum ]; then echo "✅ Installed"; else echo "❌ Not installed"; fi)"
