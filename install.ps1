# Ollama BitTorrent Lancache Installer for Windows
# Run this script as Administrator

param(
    [string]$Model = "all",
    [string]$Server = "http://localhost:8080"
)

Write-Host "🚀 Installing Ollama BitTorrent Lancache..." -ForegroundColor Green
Write-Host "Server: $Server" -ForegroundColor Cyan
Write-Host "Model: $Model" -ForegroundColor Cyan

# Check if running as Administrator
if (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Host "❌ This script requires Administrator privileges" -ForegroundColor Red
    Write-Host "Please run PowerShell as Administrator and try again" -ForegroundColor Yellow
    exit 1
}

# Check if Python is installed
try {
    $pythonVersion = python --version 2>&1
    Write-Host "Python found: $pythonVersion" -ForegroundColor Green
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

# Download seeder script
$seederUrl = "$Server/seeder.py"
$seederPath = "$env:USERPROFILE\seeder.py"
Write-Host "Downloading seeder script..." -ForegroundColor Yellow

try {
    Invoke-WebRequest -Uri $seederUrl -OutFile $seederPath -UseBasicParsing
    Write-Host "✅ Downloaded seeder script to: $seederPath" -ForegroundColor Green
} catch {
    Write-Host "❌ Failed to download seeder script: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# Create Ollama models directory if it doesn't exist
$ollamaDir = "$env:USERPROFILE\.ollama\models"
if (-not (Test-Path $ollamaDir)) {
    Write-Host "Creating Ollama models directory..." -ForegroundColor Yellow
    New-Item -ItemType Directory -Path $ollamaDir -Force | Out-Null
}

# Download models based on parameter
Write-Host "Starting model download..." -ForegroundColor Green

if ($Model -eq "all") {
    Write-Host "Downloading all available models..." -ForegroundColor Green
    python $seederPath --server $Server --download-all
} else {
    Write-Host "Downloading model: $Model" -ForegroundColor Green
    python $seederPath --server $Server --model $Model
}

if ($LASTEXITCODE -eq 0) {
    Write-Host "✅ Installation complete!" -ForegroundColor Green
    Write-Host "Models downloaded to: $ollamaDir" -ForegroundColor Green
    
    Write-Host "`n📋 Next steps:" -ForegroundColor Cyan
    Write-Host "1. Install Ollama from https://ollama.ai if not already installed" -ForegroundColor White
    Write-Host "2. Use 'ollama run <model-name>' to start using your models" -ForegroundColor White
    Write-Host "3. To seed models for other clients, run: python $seederPath --seed <model-path>" -ForegroundColor White
} else {
    Write-Host "❌ Installation failed with exit code: $LASTEXITCODE" -ForegroundColor Red
    exit $LASTEXITCODE
}
