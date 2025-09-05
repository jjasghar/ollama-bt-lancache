# Ollama BitTorrent Lancache Installer for Windows
# Run this script as Administrator
#
# IMPORTANT: Before running this script, you must set the execution policy:
# Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser

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
    Write-Host "IMPORTANT: Before running this script, set the execution policy:" -ForegroundColor Yellow
    Write-Host "Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "REQUIREMENTS:" -ForegroundColor Yellow
    Write-Host "- Python 3.8+ (will be checked and guided)" -ForegroundColor White
    Write-Host "- Microsoft Visual C++ Redistributable (will be auto-installed)" -ForegroundColor White
    Write-Host "- Administrator privileges (for installation)" -ForegroundColor White
    Write-Host ""
    Write-Host "NOTE: If you have old Visual C++ versions (2010/2012/2013), they will be" -ForegroundColor Cyan
    Write-Host "automatically removed and you'll need to restart PowerShell and run again." -ForegroundColor Cyan
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
    Write-Host "  # Download and run (recommended):" -ForegroundColor Yellow
    Write-Host "  Invoke-WebRequest -Uri 'http://192.168.1.100:8080/install.ps1' -OutFile 'install.ps1'; .\install.ps1 -List" -ForegroundColor Cyan
    Write-Host "  Invoke-WebRequest -Uri 'http://192.168.1.100:8080/install.ps1' -OutFile 'install.ps1'; .\install.ps1 -Model granite3.3:8b" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  # Direct execution (alternative):" -ForegroundColor Yellow
    Write-Host "  `$script = Invoke-WebRequest -Uri 'http://192.168.1.100:8080/install.ps1' -UseBasicParsing; Invoke-Expression \"`$(`$script.Content) -List\"" -ForegroundColor Cyan
}

# Function to list available models
function Get-AvailableModels {
    Write-Host "Fetching available models from $Server..." -ForegroundColor Cyan
    
    try {
        $response = Invoke-WebRequest -Uri "$Server/api/models" -UseBasicParsing
        $models = $response.Content | ConvertFrom-Json
        
        Write-Host ""
        Write-Host "[OK] Available Models:" -ForegroundColor Green
        Write-Host "----------------------------------------" -ForegroundColor White
        
        if ($models.Count -eq 0) {
            Write-Host "No models available on server" -ForegroundColor Yellow
        } else {
            foreach ($model in $models) {
                $sizeMB = [math]::Round($model.size / (1024 * 1024), 1)
                Write-Host "[FILE] $($model.name.PadRight(25)) $($sizeMB.ToString().PadLeft(8)) MB" -ForegroundColor White
            }
        }
        
        Write-Host "----------------------------------------" -ForegroundColor White
        Write-Host ""
        Write-Host "To download a model, use:" -ForegroundColor Cyan
        Write-Host "  .\install.ps1 -Model `"model-name`"" -ForegroundColor White
        Write-Host "  Invoke-WebRequest -Uri '$Server/install.ps1' -OutFile 'install.ps1'; .\install.ps1 -Model `"model-name`"" -ForegroundColor White
        
    } catch {
        Write-Host "[ERROR] Failed to fetch models from server: $Server" -ForegroundColor Red
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
        Write-Host "[OK] Virtual environment removed" -ForegroundColor Green
    } else {
        Write-Host "No virtual environment found at $venvPath" -ForegroundColor Yellow
    }
    
    # Also remove client script if it exists
    $clientPath = "$env:USERPROFILE\client.py"
    if (Test-Path $clientPath) {
        Write-Host "Removing client script at $clientPath..." -ForegroundColor Yellow
        Remove-Item -Force $clientPath
        Write-Host "[OK] Client script removed" -ForegroundColor Green
    }
}

# Function to check and install Visual C++ Redistributable
function Install-VisualCppRedistributable {
    Write-Host "Checking for Microsoft Visual C++ Redistributable..." -ForegroundColor Yellow
    
    # Check if VC++ Redistributable is already installed (need 2015-2022 version)
    $vcredistInstalled = $false
    $vcredistVersion = ""
    try {
        $installedPrograms = Get-WmiObject -Class Win32_Product | Where-Object { $_.Name -like "*Microsoft Visual C++*Redistributable*" }
        if ($installedPrograms) {
            foreach ($program in $installedPrograms) {
                $name = $program.Name
                # Check for 2015-2022 versions (required for libtorrent)
                if ($name -match "2015|2017|2019|2022|14\.0|15\.0|16\.0") {
                    Write-Host "[OK] Compatible Visual C++ Redistributable found: $name" -ForegroundColor Green
                    $vcredistInstalled = $true
                    $vcredistVersion = $name
                    break
                }
            }
        }
    } catch {
        # If WMI fails, try registry check
        try {
            $regPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*"
            $installedApps = Get-ItemProperty $regPath | Where-Object { $_.DisplayName -like "*Microsoft Visual C++*Redistributable*" }
            if ($installedApps) {
                foreach ($app in $installedApps) {
                    $name = $app.DisplayName
                    # Check for 2015-2022 versions (required for libtorrent)
                    if ($name -match "2015|2017|2019|2022|14\.0|15\.0|16\.0") {
                        Write-Host "[OK] Compatible Visual C++ Redistributable found: $name" -ForegroundColor Green
                        $vcredistInstalled = $true
                        $vcredistVersion = $name
                        break
                    }
                }
            }
        } catch {
            Write-Host "[WARNING] Could not check for existing Visual C++ Redistributable" -ForegroundColor Yellow
        }
    }
    
    # If only older versions found, warn and install newer version
    if (-not $vcredistInstalled) {
        try {
            $installedPrograms = Get-WmiObject -Class Win32_Product | Where-Object { $_.Name -like "*Microsoft Visual C++*Redistributable*" }
            if ($installedPrograms) {
                $oldVersions = $installedPrograms | Where-Object { $_.Name -match "2010|2012|2013" }
                if ($oldVersions) {
                    Write-Host "[WARNING] Found older Visual C++ Redistributable: $($oldVersions[0].Name)" -ForegroundColor Yellow
                    Write-Host "This version conflicts with libtorrent. Removing old version and installing compatible version..." -ForegroundColor Yellow
                    
                    # Uninstall old versions using multiple methods
                    foreach ($oldVersion in $oldVersions) {
                        Write-Host "Uninstalling $($oldVersion.Name)..." -ForegroundColor Yellow
                        $uninstalled = $false
                        
                        # Method 1: Try WMI uninstall
                        try {
                            $uninstallResult = $oldVersion.Uninstall()
                            if ($uninstallResult.ReturnValue -eq 0) {
                                Write-Host "[OK] Successfully uninstalled $($oldVersion.Name)" -ForegroundColor Green
                                $uninstalled = $true
                            } else {
                                Write-Host "[WARNING] WMI uninstall failed (Return code: $($uninstallResult.ReturnValue))" -ForegroundColor Yellow
                            }
                        } catch {
                            Write-Host "[WARNING] WMI uninstall error: $($_.Exception.Message)" -ForegroundColor Yellow
                        }
                        
                        # Method 2: Try MSI uninstall if WMI failed
                        if (-not $uninstalled) {
                            try {
                                $uninstallString = $oldVersion.IdentifyingNumber
                                if ($uninstallString) {
                                    Write-Host "Trying MSI uninstall for $($oldVersion.Name)..." -ForegroundColor Yellow
                                    $msiResult = Start-Process -FilePath "msiexec.exe" -ArgumentList "/x", $uninstallString, "/quiet", "/norestart" -Wait -PassThru
                                    if ($msiResult.ExitCode -eq 0) {
                                        Write-Host "[OK] Successfully uninstalled $($oldVersion.Name) via MSI" -ForegroundColor Green
                                        $uninstalled = $true
                                    } else {
                                        Write-Host "[WARNING] MSI uninstall failed (Exit code: $($msiResult.ExitCode))" -ForegroundColor Yellow
                                    }
                                }
                            } catch {
                                Write-Host "[WARNING] MSI uninstall error: $($_.Exception.Message)" -ForegroundColor Yellow
                            }
                        }
                        
                        # Method 3: Try registry-based uninstall
                        if (-not $uninstalled) {
                            try {
                                $regPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*"
                                $regApps = Get-ItemProperty $regPath | Where-Object { $_.DisplayName -eq $oldVersion.Name }
                                if ($regApps -and $regApps.UninstallString) {
                                    Write-Host "Trying registry-based uninstall for $($oldVersion.Name)..." -ForegroundColor Yellow
                                    $uninstallCmd = $regApps.UninstallString
                                    if ($uninstallCmd -match 'msiexec') {
                                        $msiResult = Start-Process -FilePath "msiexec.exe" -ArgumentList "/x", $regApps.PSChildName, "/quiet", "/norestart" -Wait -PassThru
                                        if ($msiResult.ExitCode -eq 0) {
                                            Write-Host "[OK] Successfully uninstalled $($oldVersion.Name) via registry MSI" -ForegroundColor Green
                                            $uninstalled = $true
                                        }
                                    }
                                }
                            } catch {
                                Write-Host "[WARNING] Registry uninstall error: $($_.Exception.Message)" -ForegroundColor Yellow
                            }
                        }
                        
                        if (-not $uninstalled) {
                            Write-Host "[WARNING] Could not uninstall $($oldVersion.Name) automatically" -ForegroundColor Yellow
                            Write-Host "You may need to uninstall it manually from Control Panel > Programs and Features" -ForegroundColor Yellow
                        }
                    }
                    
                    Write-Host ""
                    Write-Host "===============================================" -ForegroundColor Yellow
                    Write-Host "    RESTART REQUIRED" -ForegroundColor Yellow
                    Write-Host "===============================================" -ForegroundColor Yellow
                    Write-Host ""
                    Write-Host "[INFO] Old Visual C++ Redistributable versions have been removed." -ForegroundColor Cyan
                    Write-Host "You need to restart PowerShell for the changes to take effect." -ForegroundColor Yellow
                    Write-Host ""
                    Write-Host "Next steps:" -ForegroundColor White
                    Write-Host "1. Close this PowerShell window" -ForegroundColor White
                    Write-Host "2. Open a new PowerShell window as Administrator" -ForegroundColor White
                    Write-Host "3. Run the install script again:" -ForegroundColor White
                    Write-Host "   .\install.ps1 -Model $Model" -ForegroundColor Cyan
                    Write-Host ""
                    Write-Host "The script will then install the compatible Visual C++ Redistributable." -ForegroundColor Cyan
                    Write-Host ""
                    Write-Host "===============================================" -ForegroundColor Yellow
                    exit 0
                }
            }
        } catch {
            # Ignore errors in this check
        }
    }
    
    if (-not $vcredistInstalled) {
        Write-Host "[INFO] Visual C++ Redistributable not found. Installing..." -ForegroundColor Yellow
        Write-Host "This is required for libtorrent to work properly on Windows." -ForegroundColor Cyan
        
        # Download URL for Visual C++ Redistributable
        $vcredistUrl = "https://aka.ms/vs/17/release/vc_redist.x64.exe"
        $vcredistPath = "$env:TEMP\vc_redist.x64.exe"
        
        try {
            Write-Host "Downloading Visual C++ Redistributable..." -ForegroundColor Yellow
            Invoke-WebRequest -Uri $vcredistUrl -OutFile $vcredistPath -UseBasicParsing
            
            if (Test-Path $vcredistPath) {
                Write-Host "Installing Visual C++ Redistributable..." -ForegroundColor Yellow
                Write-Host "You may see a UAC prompt - please allow the installation." -ForegroundColor Cyan
                
                # Install silently
                $process = Start-Process -FilePath $vcredistPath -ArgumentList "/quiet", "/norestart" -Wait -PassThru
                
                if ($process.ExitCode -eq 0) {
                    Write-Host "[OK] Visual C++ Redistributable installed successfully!" -ForegroundColor Green
                } elseif ($process.ExitCode -eq 3010) {
                    Write-Host "[OK] Visual C++ Redistributable installed successfully (restart required)!" -ForegroundColor Green
                } else {
                    Write-Host "[WARNING] Visual C++ Redistributable installation returned code: $($process.ExitCode)" -ForegroundColor Yellow
                    Write-Host "The installation may have succeeded despite the warning." -ForegroundColor Yellow
                }
                
                # Clean up
                Remove-Item $vcredistPath -Force -ErrorAction SilentlyContinue
            } else {
                throw "Download failed"
            }
        } catch {
            Write-Host "[ERROR] Failed to download/install Visual C++ Redistributable" -ForegroundColor Red
            Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Yellow
            Write-Host ""
            Write-Host "Manual installation required:" -ForegroundColor Yellow
            Write-Host "1. Download from: https://aka.ms/vs/17/release/vc_redist.x64.exe" -ForegroundColor Cyan
            Write-Host "2. OR check if available at: $Server/downloads/" -ForegroundColor Cyan
            Write-Host "3. Install manually and run this script again" -ForegroundColor Yellow
            Write-Host ""
            Write-Host "Continuing with installation (libtorrent may fail)..." -ForegroundColor Yellow
        }
    }
}

# Function to try alternative libtorrent installation methods
function Install-LibtorrentAlternative {
    Write-Host "Trying alternative libtorrent installation methods..." -ForegroundColor Yellow
    
    # Method 1: Try installing from conda-forge (if conda is available)
    try {
        Write-Host "Trying conda installation..." -ForegroundColor Yellow
        conda install -c conda-forge libtorrent -y
        if ($LASTEXITCODE -eq 0) {
            Write-Host "[OK] libtorrent installed via conda" -ForegroundColor Green
            return $true
        }
    } catch {
        Write-Host "[INFO] conda not available, trying next method..." -ForegroundColor Yellow
    }
    
    # Method 2: Try installing specific version
    try {
        Write-Host "Trying specific libtorrent version..." -ForegroundColor Yellow
        pip install libtorrent==2.0.10
        if ($LASTEXITCODE -eq 0) {
            Write-Host "[OK] libtorrent 2.0.10 installed" -ForegroundColor Green
            return $true
        }
    } catch {
        Write-Host "[WARNING] Specific version installation failed" -ForegroundColor Yellow
    }
    
    # Method 3: Try installing from wheel
    try {
        Write-Host "Trying wheel installation..." -ForegroundColor Yellow
        pip install --only-binary=all libtorrent
        if ($LASTEXITCODE -eq 0) {
            Write-Host "[OK] libtorrent installed from wheel" -ForegroundColor Green
            return $true
        }
    } catch {
        Write-Host "[WARNING] Wheel installation failed" -ForegroundColor Yellow
    }
    
    return $false
}

# Function to setup virtual environment
function Initialize-VirtualEnvironment {
    # Check if Python is installed
    try {
        $pythonVersion = python --version 2>&1
        if ($pythonVersion -match "Python was not found") {
            throw "Python not found"
        }
        Write-Host "[OK] Python found: $pythonVersion" -ForegroundColor Green
    } catch {
        Write-Host ""
        Write-Host "===============================================" -ForegroundColor Red
        Write-Host "           PYTHON NOT FOUND ERROR" -ForegroundColor Red
        Write-Host "===============================================" -ForegroundColor Red
        Write-Host ""
        Write-Host "[ERROR] Python 3.8+ is required but not found on this system!" -ForegroundColor Red
        Write-Host ""
        Write-Host "To fix this issue:" -ForegroundColor Yellow
        Write-Host "1. Download Python from: https://python.org/downloads/" -ForegroundColor Cyan
        Write-Host "2. OR check if Python installer is available at:" -ForegroundColor Cyan
        Write-Host "   $Server/downloads/" -ForegroundColor Cyan
        Write-Host "3. Install Python 3.8 or newer" -ForegroundColor Yellow
        Write-Host "4. Make sure to check 'Add Python to PATH' during installation" -ForegroundColor Yellow
        Write-Host "5. Restart PowerShell and run this script again" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "If you continue to have issues, try running:" -ForegroundColor White
        Write-Host "  py --version" -ForegroundColor Cyan
        Write-Host "  python3 --version" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "===============================================" -ForegroundColor Red
        exit 1
    }
    
    # Check Python version
    $pythonVersionOutput = python --version 2>&1
    if ($pythonVersionOutput -match "Python (\d+)\.(\d+)") {
        $major = [int]$matches[1]
        $minor = [int]$matches[2]
        
        if ($major -lt 3 -or ($major -eq 3 -and $minor -lt 8)) {
            Write-Host "[ERROR] Python 3.8+ required. Found: $major.$minor" -ForegroundColor Red
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
    try {
        python -m venv $venvPath
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to create virtual environment"
        }
    } catch {
        Write-Host ""
        Write-Host "===============================================" -ForegroundColor Red
        Write-Host "      VIRTUAL ENVIRONMENT CREATION FAILED" -ForegroundColor Red
        Write-Host "===============================================" -ForegroundColor Red
        Write-Host ""
        Write-Host "[ERROR] Failed to create virtual environment with Python!" -ForegroundColor Red
        Write-Host "This usually means Python is not properly installed or not in PATH." -ForegroundColor Yellow
        Write-Host ""
        Write-Host "To fix this issue:" -ForegroundColor Yellow
        Write-Host "1. Download Python from: https://python.org/downloads/" -ForegroundColor Cyan
        Write-Host "2. OR check if Python installer is available at:" -ForegroundColor Cyan
        Write-Host "   $Server/downloads/" -ForegroundColor Cyan
        Write-Host "3. Install Python 3.8 or newer" -ForegroundColor Yellow
        Write-Host "4. Make sure to check 'Add Python to PATH' during installation" -ForegroundColor Yellow
        Write-Host "5. Restart PowerShell and run this script again" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "===============================================" -ForegroundColor Red
        exit 1
    }
    
    # Activate virtual environment
    Write-Host "Activating virtual environment..." -ForegroundColor Yellow
    try {
        & "$venvPath\Scripts\Activate.ps1"
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to activate virtual environment"
        }
    } catch {
        Write-Host ""
        Write-Host "===============================================" -ForegroundColor Red
        Write-Host "    VIRTUAL ENVIRONMENT ACTIVATION FAILED" -ForegroundColor Red
        Write-Host "===============================================" -ForegroundColor Red
        Write-Host ""
        Write-Host "[ERROR] Failed to activate virtual environment!" -ForegroundColor Red
        Write-Host "The virtual environment was created but cannot be activated." -ForegroundColor Yellow
        Write-Host ""
        Write-Host "This might be due to:" -ForegroundColor Yellow
        Write-Host "1. PowerShell execution policy restrictions" -ForegroundColor White
        Write-Host "2. Missing activation script" -ForegroundColor White
        Write-Host "3. Corrupted virtual environment" -ForegroundColor White
        Write-Host ""
        Write-Host "Try running: .\install.ps1 -Clean" -ForegroundColor Cyan
        Write-Host "Then run this script again" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "===============================================" -ForegroundColor Red
        exit 1
    }
    
    # Install required packages
    Write-Host "Installing required packages..." -ForegroundColor Yellow
    try {
        # Upgrade pip using the recommended method
        python -m pip install --upgrade pip
        if ($LASTEXITCODE -ne 0) {
            Write-Host "[WARNING] Failed to upgrade pip, continuing with existing version..." -ForegroundColor Yellow
        } else {
            Write-Host "[OK] pip upgraded successfully" -ForegroundColor Green
        }
        
        Write-Host "Installing libtorrent (this may take a few minutes)..." -ForegroundColor Yellow
        pip install libtorrent
        if ($LASTEXITCODE -ne 0) {
            Write-Host "[WARNING] libtorrent installation failed. This is common on Windows." -ForegroundColor Yellow
            Write-Host "You may need to install Microsoft Visual C++ Redistributable first." -ForegroundColor Yellow
            Write-Host "Continuing with installation..." -ForegroundColor Yellow
        } else {
            Write-Host "[OK] libtorrent installed successfully" -ForegroundColor Green
            
            # Test if libtorrent can actually load
            Write-Host "Testing libtorrent import..." -ForegroundColor Yellow
            $testScript = @"
import sys
try:
    import libtorrent as lt
    print("SUCCESS: libtorrent imported successfully")
    sys.exit(0)
except ImportError as e:
    print(f"ERROR: {e}")
    sys.exit(1)
"@
            $testScript | python
            if ($LASTEXITCODE -ne 0) {
                Write-Host "[WARNING] libtorrent installed but cannot be imported!" -ForegroundColor Yellow
                Write-Host "This usually means Visual C++ Redistributable is missing or incompatible." -ForegroundColor Yellow
                
                # Try to diagnose the issue
                Write-Host "Diagnosing libtorrent DLL issue..." -ForegroundColor Yellow
                $diagnosticScript = @"
import sys
import os
import site

print("Python version:", sys.version)
print("Python executable:", sys.executable)
print("Site packages:", site.getsitepackages())

# Check for libtorrent package
try:
    import pkg_resources
    dist = pkg_resources.get_distribution('libtorrent')
    print("libtorrent version:", dist.version)
    print("libtorrent location:", dist.location)
    
    # Check for DLL files
    libtorrent_path = os.path.join(dist.location, 'libtorrent')
    if os.path.exists(libtorrent_path):
        print("libtorrent package directory exists")
        dll_files = [f for f in os.listdir(libtorrent_path) if f.endswith('.dll')]
        print("DLL files found:", dll_files)
    else:
        print("libtorrent package directory not found")
        
except Exception as e:
    print("Error checking libtorrent package:", e)

# Check PATH
print("PATH environment variable:")
for path in os.environ.get('PATH', '').split(';'):
    if 'visual' in path.lower() or 'redist' in path.lower() or 'vcredist' in path.lower():
        print("  Found VC++ path:", path)
"@
                $diagnosticScript | python
                
                Write-Host ""
                Write-Host "===============================================" -ForegroundColor Red
                Write-Host "    LIBTORRENT DLL TROUBLESHOOTING" -ForegroundColor Red
                Write-Host "===============================================" -ForegroundColor Red
                Write-Host ""
                Write-Host "The libtorrent package installed but cannot load its DLL dependencies." -ForegroundColor Yellow
                Write-Host ""
                Write-Host "Trying alternative installation methods..." -ForegroundColor Yellow
                
                # Try alternative installation methods
                $alternativeSuccess = Install-LibtorrentAlternative
                
                if (-not $alternativeSuccess) {
                    Write-Host ""
                    Write-Host "===============================================" -ForegroundColor Red
                    Write-Host "    LIBTORRENT INSTALLATION FAILED" -ForegroundColor Red
                    Write-Host "===============================================" -ForegroundColor Red
                    Write-Host ""
                    Write-Host "All libtorrent installation methods failed." -ForegroundColor Yellow
                    Write-Host ""
                    Write-Host "Try these manual solutions:" -ForegroundColor Yellow
                    Write-Host ""
                    Write-Host "1. RESTART POWERSHELL and run the script again:" -ForegroundColor Cyan
                    Write-Host "   .\install.ps1 -Model $Model" -ForegroundColor White
                    Write-Host ""
                    Write-Host "2. Manual libtorrent reinstall:" -ForegroundColor Cyan
                    Write-Host "   pip uninstall libtorrent -y" -ForegroundColor White
                    Write-Host "   pip install libtorrent==2.0.10" -ForegroundColor White
                    Write-Host ""
                    Write-Host "3. Alternative: Use manual torrent download:" -ForegroundColor Cyan
                    Write-Host "   Go to: $Server" -ForegroundColor White
                    Write-Host "   Click 'Download Torrent' for your model" -ForegroundColor White
                    Write-Host "   Use any BitTorrent client to download" -ForegroundColor White
                    Write-Host ""
                    Write-Host "===============================================" -ForegroundColor Red
                    Write-Host ""
                    Write-Host "Continuing with installation (model download may fail)..." -ForegroundColor Yellow
                } else {
                    Write-Host "[OK] Alternative libtorrent installation successful!" -ForegroundColor Green
                }
            } else {
                Write-Host "[OK] libtorrent import test passed" -ForegroundColor Green
            }
        }
        
        pip install requests
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to install requests"
        } else {
            Write-Host "[OK] requests installed successfully" -ForegroundColor Green
        }
        
        Write-Host "[OK] Required packages installed" -ForegroundColor Green
    } catch {
        Write-Host ""
        Write-Host "===============================================" -ForegroundColor Red
        Write-Host "      PACKAGE INSTALLATION FAILED" -ForegroundColor Red
        Write-Host "===============================================" -ForegroundColor Red
        Write-Host ""
        Write-Host "[ERROR] Failed to install required Python packages!" -ForegroundColor Red
        Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "Common solutions:" -ForegroundColor Yellow
        Write-Host "1. Install Microsoft Visual C++ Redistributable:" -ForegroundColor Cyan
        Write-Host "   https://aka.ms/vs/17/release/vc_redist.x64.exe" -ForegroundColor Cyan
        Write-Host "2. OR check if redistributable is available at:" -ForegroundColor Cyan
        Write-Host "   $Server/downloads/" -ForegroundColor Cyan
        Write-Host "3. Restart PowerShell and run this script again" -ForegroundColor Yellow
        Write-Host "4. If libtorrent fails, you can still use manual torrent downloads" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "===============================================" -ForegroundColor Red
        exit 1
    }
}

# Function to download client script
function Get-ClientScript {
    $clientUrl = "$Server/client.py"
    $clientPath = "$env:USERPROFILE\client.py"
    Write-Host "Downloading client script..." -ForegroundColor Yellow
    
    try {
        Invoke-WebRequest -Uri $clientUrl -OutFile $clientPath -UseBasicParsing
        Write-Host "[OK] Downloaded client script to: $clientPath" -ForegroundColor Green
    } catch {
        Write-Host "[ERROR] Failed to download client script: $($_.Exception.Message)" -ForegroundColor Red
        exit 1
    }
}

# Function to download model using fallback method (no libtorrent)
function Get-ModelFallback {
    if ([string]::IsNullOrEmpty($Model)) {
        Write-Host "[ERROR] No model specified. Use -List to see available models or -Model `"name`" to download" -ForegroundColor Red
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
    
    Write-Host "[START] Starting fallback model download (HTTP method)..." -ForegroundColor Green
    Write-Host "Model: $Model" -ForegroundColor Cyan
    Write-Host "Server: $Server" -ForegroundColor Cyan
    Write-Host "Output: $outputDir" -ForegroundColor Cyan
    
    try {
        # Get model information from server
        Write-Host "Fetching model information..." -ForegroundColor Yellow
        $modelsResponse = Invoke-WebRequest -Uri "$Server/api/models" -UseBasicParsing
        $models = $modelsResponse.Content | ConvertFrom-Json
        
        $targetModel = $models | Where-Object { $_.name -eq $Model }
        if (-not $targetModel) {
            Write-Host "[ERROR] Model '$Model' not found on server" -ForegroundColor Red
            Write-Host "Available models:" -ForegroundColor Yellow
            foreach ($model in $models) {
                Write-Host "  - $($model.name)" -ForegroundColor White
            }
            exit 1
        }
        
        Write-Host "[OK] Found model: $($targetModel.name)" -ForegroundColor Green
        Write-Host "Size: $([math]::Round($targetModel.size / (1024 * 1024), 1)) MB" -ForegroundColor Cyan
        
        # Download torrent file
        Write-Host "Downloading torrent file..." -ForegroundColor Yellow
        $torrentUrl = "$Server/api/models/$Model/torrent"
        $torrentPath = "$outputDir\$($Model.Replace(':', '_')).torrent"
        
        try {
            Invoke-WebRequest -Uri $torrentUrl -OutFile $torrentPath -UseBasicParsing
            Write-Host "[OK] Downloaded torrent file: $torrentPath" -ForegroundColor Green
        } catch {
            Write-Host "[ERROR] Failed to download torrent file: $($_.Exception.Message)" -ForegroundColor Red
            exit 1
        }
        
        Write-Host ""
        Write-Host "===============================================" -ForegroundColor Green
        Write-Host "    FALLBACK DOWNLOAD COMPLETE" -ForegroundColor Green
        Write-Host "===============================================" -ForegroundColor Green
        Write-Host ""
        Write-Host "[OK] Torrent file downloaded successfully!" -ForegroundColor Green
        Write-Host "Location: $torrentPath" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "Next steps:" -ForegroundColor Yellow
        Write-Host "1. Install a BitTorrent client (if not already installed):" -ForegroundColor White
        Write-Host "   - qBittorrent: https://www.qbittorrent.org/" -ForegroundColor Cyan
        Write-Host "   - Transmission: https://transmissionbt.com/" -ForegroundColor Cyan
        Write-Host "   - Deluge: https://www.deluge-torrent.org/" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "2. Open the torrent file with your BitTorrent client:" -ForegroundColor White
        Write-Host "   $torrentPath" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "3. The client will download the model files to:" -ForegroundColor White
        Write-Host "   $outputDir" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "4. Once downloaded, you can use the model with Ollama:" -ForegroundColor White
        Write-Host "   ollama run $Model" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "===============================================" -ForegroundColor Green
        
    } catch {
        Write-Host "[ERROR] Fallback download failed: $($_.Exception.Message)" -ForegroundColor Red
        exit 1
    }
}

# Function to download model
function Get-Model {
    if ([string]::IsNullOrEmpty($Model)) {
        Write-Host "[ERROR] No model specified. Use -List to see available models or -Model `"name`" to download" -ForegroundColor Red
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
    Write-Host "[START] Starting model download..." -ForegroundColor Green
    Write-Host "Model: $Model" -ForegroundColor Cyan
    Write-Host "Server: $Server" -ForegroundColor Cyan
    Write-Host "Output: $outputDir" -ForegroundColor Cyan
    
    $clientPath = "$env:USERPROFILE\client.py"
    if (-not (Test-Path $clientPath)) {
        Write-Host "[ERROR] Client script not found. Please run setup first." -ForegroundColor Red
        exit 1
    }
    
    # Activate virtual environment
    & "$env:USERPROFILE\.ollama-bt-venv\Scripts\Activate.ps1"
    
    # Download the model
    try {
        $output = python $clientPath --server $Server --model $Model --output $outputDir 2>&1
        if ($LASTEXITCODE -ne 0) {
            # Check for specific error types
            if ($output -match "DLL load failed while importing libtorrent" -or $output -match "ImportError.*libtorrent") {
                throw "LIBTORRENT_DLL_ERROR"
            } elseif ($output -match "ModuleNotFoundError.*libtorrent" -or $output -match "No module named 'libtorrent'") {
                throw "LIBTORRENT_MISSING"
            } else {
                throw "PYTHON_EXECUTION_ERROR"
            }
        }
    } catch {
        $errorType = $_.Exception.Message
        
        if ($errorType -eq "LIBTORRENT_DLL_ERROR") {
            Write-Host ""
            Write-Host "===============================================" -ForegroundColor Red
            Write-Host "      LIBTORRENT DLL LOAD FAILED" -ForegroundColor Red
            Write-Host "===============================================" -ForegroundColor Red
            Write-Host ""
            Write-Host "[ERROR] libtorrent library cannot load its required DLL files!" -ForegroundColor Red
            Write-Host "This is a common issue on Windows. Using fallback download method..." -ForegroundColor Yellow
            Write-Host ""
            Write-Host "===============================================" -ForegroundColor Red
            Write-Host ""
            
            # Use fallback method
            Get-ModelFallback
            return
        } elseif ($errorType -eq "LIBTORRENT_MISSING") {
            Write-Host ""
            Write-Host "===============================================" -ForegroundColor Red
            Write-Host "        LIBTORRENT PACKAGE MISSING" -ForegroundColor Red
            Write-Host "===============================================" -ForegroundColor Red
            Write-Host ""
            Write-Host "[ERROR] libtorrent package is not installed!" -ForegroundColor Red
            Write-Host "Using fallback download method..." -ForegroundColor Yellow
            Write-Host ""
            Write-Host "===============================================" -ForegroundColor Red
            Write-Host ""
            
            # Use fallback method
            Get-ModelFallback
            return
        } else {
            Write-Host ""
            Write-Host "===============================================" -ForegroundColor Red
            Write-Host "         PYTHON EXECUTION FAILED" -ForegroundColor Red
            Write-Host "===============================================" -ForegroundColor Red
            Write-Host ""
            Write-Host "[ERROR] Failed to execute Python script for model download!" -ForegroundColor Red
            Write-Host "Error details: $output" -ForegroundColor Yellow
            Write-Host ""
            Write-Host "To fix this issue:" -ForegroundColor Yellow
            Write-Host "1. Download Python from: https://python.org/downloads/" -ForegroundColor Cyan
            Write-Host "2. OR check if Python installer is available at:" -ForegroundColor Cyan
            Write-Host "   $Server/downloads/" -ForegroundColor Cyan
            Write-Host "3. Install Python 3.8 or newer" -ForegroundColor Yellow
            Write-Host "4. Make sure to check 'Add Python to PATH' during installation" -ForegroundColor Yellow
            Write-Host "5. Restart PowerShell and run this script again" -ForegroundColor Yellow
            Write-Host ""
            Write-Host "===============================================" -ForegroundColor Red
        }
        exit 1
    }
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "[OK] Model download complete!" -ForegroundColor Green
        Write-Host "Model downloaded to: $outputDir" -ForegroundColor Green
        
        if (-not $Test) {
            Write-Host ""
            Write-Host "[INFO] Next steps:" -ForegroundColor Cyan
            Write-Host "1. Install Ollama from https://ollama.ai if not already installed" -ForegroundColor White
            Write-Host "2. Use 'ollama run $Model' to start using your model" -ForegroundColor White
        }
    } else {
        Write-Host "[ERROR] Model download failed with exit code: $LASTEXITCODE" -ForegroundColor Red
        exit $LASTEXITCODE
    }
}

# Main execution
try {
    # Check if running as Administrator (only for installation, not for listing/cleaning)
    if (-not $Clean -and -not $List) {
        if (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
            Write-Host "[ERROR] This script requires Administrator privileges for installation" -ForegroundColor Red
            Write-Host "This is needed to install Visual C++ Redistributable and set up the environment." -ForegroundColor Yellow
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
        Write-Host "[WARNING] No model specified. Showing available models..." -ForegroundColor Yellow
        Get-AvailableModels
        exit 0
    }
    
    # Setup environment and download model
    Write-Host "[START] Installing Ollama BitTorrent Lancache..." -ForegroundColor Green
    Write-Host "Server: $Server" -ForegroundColor Cyan
    Write-Host "Model: $Model" -ForegroundColor Cyan
    
    # Check and install Visual C++ Redistributable (required for libtorrent)
    Install-VisualCppRedistributable
    
    Initialize-VirtualEnvironment
    Get-ClientScript
    Get-Model
    
} catch {
    Write-Host "[ERROR] An error occurred: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}