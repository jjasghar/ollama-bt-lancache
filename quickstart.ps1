# Ollama BitTorrent Lancache Quick Start Script for Windows
# Run this script as Administrator

param(
    [string]$Port = "8081"
)

# Function to print colored output
function Write-Status {
    param([string]$Message)
    Write-Host "🚀 $Message" -ForegroundColor Green
}

function Write-Info {
    param([string]$Message)
    Write-Host $Message -ForegroundColor Cyan
}

function Write-Warning {
    param([string]$Message)
    Write-Host $Message -ForegroundColor Yellow
}

function Write-Error {
    param([string]$Message)
    Write-Host "❌ $Message" -ForegroundColor Red
}

function Write-Success {
    param([string]$Message)
    Write-Host "✅ $Message" -ForegroundColor Green
}

# Check if running as Administrator
if (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Error "This script requires Administrator privileges"
    Write-Host "Please run PowerShell as Administrator and try again" -ForegroundColor Yellow
    exit 1
}

# Check dependencies
function Test-Dependencies {
    Write-Info "Checking dependencies..."
    
    # Check Go
    try {
        $goVersion = go version 2>&1
        Write-Success "Go found: $goVersion"
    } catch {
        Write-Error "Go not found. Please install Go 1.21+ from https://golang.org"
        exit 1
    }
    
    # Check Python
    try {
        $pythonVersion = python --version 2>&1
        Write-Success "Python found: $pythonVersion"
    } catch {
        Write-Error "Python not found. Please install Python 3.8+ from https://python.org"
        exit 1
    }
    
    # Check Git
    try {
        $gitVersion = git --version 2>&1
        Write-Success "Git found: $gitVersion"
    } catch {
        Write-Error "Git not found. Please install Git from https://git-scm.com"
        exit 1
    }
}

# Setup tracker
function Setup-Tracker {
    Write-Info "Setting up BitTorrent tracker..."
    
    if (-not (Test-Path "tracker\tracker.exe")) {
        if (-not (Test-Path "tracker\privtracker")) {
            Write-Info "Cloning privtracker repository..."
            Set-Location tracker
            git clone https://github.com/meehow/privtracker.git
            Set-Location ..
        }
        
        Write-Info "Building tracker..."
        Set-Location tracker\privtracker
        go build -o tracker.exe
        Copy-Item tracker.exe ..\tracker.exe
        Set-Location ..\..
        Write-Success "Tracker built successfully"
    } else {
        Write-Info "Tracker already exists"
    }
}

# Build server
function Build-Server {
    Write-Info "Building Go server..."
    Set-Location server
    go mod download
    go build -o ollama-bt-lancache.exe
    Set-Location ..
    Write-Success "Server built successfully"
}

# Start services
function Start-Services {
    Write-Info "Starting services..."
    
    # Start tracker in background
    Write-Info "Starting BitTorrent tracker on port 8080..."
    Start-Process -FilePath "tracker\tracker.exe" -WindowStyle Hidden -RedirectStandardOutput "tracker\tracker.log" -RedirectStandardError "tracker\tracker.log"
    Start-Sleep -Seconds 2
    
    # Start server in background
    Write-Info "Starting main server on port $Port..."
    $serverProcess = Start-Process -FilePath "server\ollama-bt-lancache.exe" -ArgumentList "--port", $Port -WindowStyle Hidden -RedirectStandardOutput "server\server.log" -RedirectStandardError "server\server.log" -PassThru
    
    Start-Sleep -Seconds 2
    
    Write-Success "Services started!"
    Write-Info "Tracker running on port 8080"
    Write-Info "Server running on port $Port (PID: $($serverProcess.Id))"
    Write-Info "Tracker log: tracker\tracker.log"
    Write-Info "Server log: server\server.log"
    
    Write-Info "Web interface available at: http://localhost:$Port"
    Write-Info "Press Enter to stop all services"
    
    # Wait for user input
    Read-Host
    
    # Stop services
    Write-Info "Stopping services..."
    Stop-Process -Id $serverProcess.Id -Force
    Get-Process -Name "tracker" -ErrorAction SilentlyContinue | Stop-Process -Force
    Write-Success "Services stopped"
}

# Main function
function Main {
    Write-Status "Ollama BitTorrent Lancache Quick Start for Windows"
    Write-Info "This script will set up and start all services"
    
    Test-Dependencies
    Setup-Tracker
    Build-Server
    Start-Services
}

# Run main function
Main
