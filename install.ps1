# Ollama BitTorrent Lancache Installer for Windows
# Run this script as Administrator

param(
    [string]$Model = "",
    [string]$Server = "http://localhost:8080",
    [switch]$Test,
    [switch]$Clean,
    [switch]$List
)

# Function to show usage
function Show-Usage {
    Write-Host "Usage: .\install.ps1 [OPTIONS]" -ForegroundColor White
    Write-Host ""
    Write-Host "Options:" -ForegroundColor White
    Write-Host "  -Model MODEL     Download specific model (e.g., granite3.3:8b)" -ForegroundColor White
    Write-Host "  -Server URL      Server URL (default: http://localhost:8080)" -ForegroundColor White
    Write-Host "  -Test            Download to current directory instead of ~/.ollama/models" -ForegroundColor White
    Write-Host "  -Clean           Remove virtual environment and exit" -ForegroundColor White
    Write-Host "  -List            List available models from server" -ForegroundColor White
    Write-Host "  -Help            Show this help message" -ForegroundColor White
    Write-Host ""
    Write-Host "Examples:" -ForegroundColor White
    Write-Host "  .\install.ps1 -List                                    # List available models" -ForegroundColor Cyan
    Write-Host "  .\install.ps1 -Model granite3.3:8b                    # Download specific model" -ForegroundColor Cyan
    Write-Host "  .\install.ps1 -Model phi3:mini -Server http://192.168.1.100:8080  # Download from specific server" -ForegroundColor Cyan
    Write-Host "  .\install.ps1 -Test -Model granite3.3:8b             # Download to current directory" -ForegroundColor Cyan
    Write-Host "  .\install.ps1 -Clean                                  # Remove virtual environment" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "One-liner examples:" -ForegroundColor White
    Write-Host "  Invoke-WebRequest -Uri 'http://192.168.1.100:8080/install.ps1' | Invoke-Expression -ArgumentList '-Model granite3.3:8b'" -ForegroundColor Cyan
    Write-Host "  Invoke-WebRequest -Uri 'http://192.168.1.100:8080/install.ps1' | Invoke-Expression -ArgumentList '-List'" -ForegroundColor Cyan
}

# Function to list available models
function Get-AvailableModels {
    Write-Host "Fetching available models from $Server..." -ForegroundColor Cyan
    
    try {
        $response = Invoke-WebRequest -Uri "$Server/api/models" -UseBasicParsing
        $models = $response.Content | ConvertFrom-Json
        
        Write-Host ""
        Write-Host "✅ Available Models:" -ForegroundColor Green
        Write-Host "----------------------------------------" -ForegroundColor White
        
        if ($models.Count -eq 0) {
            Write-Host "No models available on server" -ForegroundColor Yellow
        } else {
            foreach ($model in $models) {
                $sizeMB = [math]::Round($model.size / (1024 * 1024), 1)
                Write-Host "📁 $($model.name.PadRight(25)) $($sizeMB.ToString().PadLeft(8)) MB" -ForegroundColor White
            }
        }
        
        Write-Host "----------------------------------------" -ForegroundColor White
        Write-Host ""
        Write-Host "To download a model, use:" -ForegroundColor Cyan
        Write-Host "  .\install.ps1 -Model <model-name>" -ForegroundColor White
        Write-Host "  Invoke-WebRequest -Uri '$Server/install.ps1' | Invoke-Expression -ArgumentList '-Model <model-name>'" -ForegroundColor White
        
    } catch {
        Write-Host "❌ Failed to fetch models from server: $Server" -ForegroundColor Red
        Write-Host "Make sure the server is running and accessible" -ForegroundColor Yellow
        exit 1
    }
}

# Function to clean virtual environment
function Remove-VirtualEnvironment {
    $venvPath = "$env:USERPROFILE\.ollama-bt-venv"
    
    if (Test-Path $venvPath) {
        Write-Host "Removing virtual environment at $venvPath..." -ForegroundColor Yellow
        Remove-Item -Recurse -Force $venvPath
        Write-Host "✅ Virtual environment removed" -ForegroundColor Green
    } else {
        Write-Host "No virtual environment found at $venvPath" -ForegroundColor Yellow
    }
    
    # Also remove client script if it exists
    $clientPath = "$env:USERPROFILE\client.py"
    if (Test-Path $clientPath) {
        Write-Host "Removing client script at $clientPath..." -ForegroundColor Yellow
        Remove-Item -Force $clientPath
        Write-Host "✅ Client script removed" -ForegroundColor Green
    }
}

# Function to setup virtual environment
function Initialize-VirtualEnvironment {
    # Check if Python is installed
    try {
        $pythonVersion = python --version 2>&1
        Write-Host "✅ Python found: $pythonVersion" -ForegroundColor Green
    } catch {
        Write-Host "❌ Python not found. Please install Python 3.8+ from https://python.org" -ForegroundColor Red
        Write-Host "After installing Python, restart PowerShell and run this script again" -ForegroundColor Yellow
        exit 1
    }
    
    # Check Python version
    $pythonVersionOutput = python --version 2>&1
    if ($pythonVersionOutput -match "Python (\d+)\.(\d+)") {
        $major = [int]$matches[1]
        $minor = [int]$matches[2]
        
        if ($major -lt 3 -or ($major -eq 3 -and $minor -lt 8)) {
            Write-Host "❌ Python 3.8+ required. Found: $major.$minor" -ForegroundColor Red
            exit 1
        }
    }
    
    # Create virtual environment
    $venvPath = "$env:USERPROFILE\.ollama-bt-venv"
    if (Test-Path $venvPath) {
        Write-Host "Virtual environment already exists at $venvPath" -ForegroundColor Yellow
        Write-Host "Removing existing environment..." -ForegroundColor Yellow
        Remove-Item -Recurse -Force $venvPath
    }
    
    Write-Host "Creating virtual environment..." -ForegroundColor Yellow
    python -m venv $venvPath
    
    # Activate virtual environment
    Write-Host "Activating virtual environment..." -ForegroundColor Yellow
    & "$venvPath\Scripts\Activate.ps1"
    
    # Install required packages
    Write-Host "Installing required packages..." -ForegroundColor Yellow
    pip install --upgrade pip
    pip install libtorrent requests
}

# Function to download client script
function Get-ClientScript {
    $clientUrl = "$Server/client.py"
    $clientPath = "$env:USERPROFILE\client.py"
    Write-Host "Downloading client script..." -ForegroundColor Yellow
    
    try {
        Invoke-WebRequest -Uri $clientUrl -OutFile $clientPath -UseBasicParsing
        Write-Host "✅ Downloaded client script to: $clientPath" -ForegroundColor Green
    } catch {
        Write-Host "❌ Failed to download client script: $($_.Exception.Message)" -ForegroundColor Red
        exit 1
    }
}

# Function to download model
function Get-Model {
    if ([string]::IsNullOrEmpty($Model)) {
        Write-Host "❌ No model specified. Use -List to see available models or -Model <name> to download" -ForegroundColor Red
        exit 1
    }
    
    # Determine output directory
    if ($Test) {
        $outputDir = "$(Get-Location)\downloads"
        Write-Host "Test mode: downloading to $outputDir" -ForegroundColor Cyan
    } else {
        $outputDir = "$env:USERPROFILE\.ollama\models"
        Write-Host "Downloading to Ollama directory: $outputDir" -ForegroundColor Cyan
    }
    
    # Create output directory
    if (-not (Test-Path $outputDir)) {
        New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
    }
    
    # Download model using client script
    Write-Host "🚀 Starting model download..." -ForegroundColor Green
    Write-Host "Model: $Model" -ForegroundColor Cyan
    Write-Host "Server: $Server" -ForegroundColor Cyan
    Write-Host "Output: $outputDir" -ForegroundColor Cyan
    
    $clientPath = "$env:USERPROFILE\client.py"
    if (-not (Test-Path $clientPath)) {
        Write-Host "❌ Client script not found. Please run setup first." -ForegroundColor Red
        exit 1
    }
    
    # Activate virtual environment
    & "$env:USERPROFILE\.ollama-bt-venv\Scripts\Activate.ps1"
    
    # Download the model
    python $clientPath --server $Server --model $Model --output $outputDir
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "✅ Model download complete!" -ForegroundColor Green
        Write-Host "Model downloaded to: $outputDir" -ForegroundColor Green
        
        if (-not $Test) {
            Write-Host ""
            Write-Host "📋 Next steps:" -ForegroundColor Cyan
            Write-Host "1. Install Ollama from https://ollama.ai if not already installed" -ForegroundColor White
            Write-Host "2. Use 'ollama run $Model' to start using your model" -ForegroundColor White
        }
    } else {
        Write-Host "❌ Model download failed with exit code: $LASTEXITCODE" -ForegroundColor Red
        exit $LASTEXITCODE
    }
}

# Main execution
try {
    # Check if running as Administrator (only for installation, not for listing/cleaning)
    if (-not $Clean -and -not $List) {
        if (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
            Write-Host "❌ This script requires Administrator privileges for installation" -ForegroundColor Red
            Write-Host "Please run PowerShell as Administrator and try again" -ForegroundColor Yellow
            exit 1
        }
    }
    
    # Handle special modes
    if ($Clean) {
        Remove-VirtualEnvironment
        exit 0
    }
    
    if ($List) {
        Get-AvailableModels
        exit 0
    }
    
    # If no model specified, show available models
    if ([string]::IsNullOrEmpty($Model)) {
        Write-Host "⚠️ No model specified. Showing available models..." -ForegroundColor Yellow
        Get-AvailableModels
        exit 0
    }
    
    # Setup environment and download model
    Write-Host "🚀 Installing Ollama BitTorrent Lancache..." -ForegroundColor Green
    Write-Host "Server: $Server" -ForegroundColor Cyan
    Write-Host "Model: $Model" -ForegroundColor Cyan
    
    Initialize-VirtualEnvironment
    Get-ClientScript
    Get-Model
    
} catch {
    Write-Host "❌ An error occurred: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}