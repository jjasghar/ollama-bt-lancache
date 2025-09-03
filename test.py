#!/usr/bin/env python3
"""
Test script for Ollama BitTorrent Lancache
This script tests various components to ensure everything is working correctly
"""

import os
import sys
import time
import requests
import subprocess
import tempfile
import shutil
from pathlib import Path

def print_status(message):
    print(f"🚀 {message}")

def print_info(message):
    print(f"📋 {message}")

def print_success(message):
    print(f"✅ {message}")

def print_error(message):
    print(f"❌ {message}")

def print_warning(message):
    print(f"⚠️  {message}")

def test_server_connection(server_url):
    """Test if the server is accessible"""
    print_info("Testing server connection...")
    
    try:
        response = requests.get(f"{server_url}/api/models", timeout=10)
        if response.status_code == 200:
            print_success(f"Server accessible at {server_url}")
            return True
        else:
            print_error(f"Server returned status code: {response.status_code}")
            return False
    except requests.exceptions.RequestException as e:
        print_error(f"Failed to connect to server: {e}")
        return False

def test_tracker_connection(tracker_url):
    """Test if the tracker is accessible"""
    print_info("Testing tracker connection...")
    
    try:
        response = requests.get(tracker_url, timeout=10)
        if response.status_code == 200:
            print_success(f"Tracker accessible at {tracker_url}")
            return True
        else:
            print_warning(f"Tracker returned status code: {response.status_code}")
            return False
    except requests.exceptions.RequestException as e:
        print_warning(f"Failed to connect to tracker: {e}")
        return False

def test_python_dependencies():
    """Test if required Python packages are available"""
    print_info("Testing Python dependencies...")
    
    required_packages = ['libtorrent', 'requests']
    missing_packages = []
    
    for package in required_packages:
        try:
            __import__(package)
            print_success(f"{package} available")
        except ImportError:
            print_error(f"{package} not available")
            missing_packages.append(package)
    
    if missing_packages:
        print_warning(f"Missing packages: {', '.join(missing_packages)}")
        print_info("Install with: pip install " + " ".join(missing_packages))
        return False
    
    return True

def test_seeder_script(server_url):
    """Test the seeder script functionality"""
    print_info("Testing seeder script...")
    
    try:
        # Test help command
        result = subprocess.run([
            sys.executable, "seeder.py", "--help"
        ], capture_output=True, text=True, timeout=30)
        
        if result.returncode == 0:
            print_success("Seeder script help command works")
        else:
            print_error("Seeder script help command failed")
            return False
        
        # Test list models command
        result = subprocess.run([
            sys.executable, "seeder.py", "--server", server_url, "--list"
        ], capture_output=True, text=True, timeout=30)
        
        if result.returncode == 0:
            print_success("Seeder script list command works")
        else:
            print_warning("Seeder script list command failed (server may not be running)")
        
        return True
        
    except subprocess.TimeoutExpired:
        print_error("Seeder script test timed out")
        return False
    except Exception as e:
        print_error(f"Seeder script test failed: {e}")
        return False

def test_installation_scripts():
    """Test if installation scripts exist and are executable"""
    print_info("Testing installation scripts...")
    
    scripts = [
        ("install.sh", "Bash installation script"),
        ("install.ps1", "PowerShell installation script")
    ]
    
    all_good = True
    
    for script_name, description in scripts:
        if os.path.exists(script_name):
            if os.access(script_name, os.X_OK) or script_name.endswith('.ps1'):
                print_success(f"{description} exists and is accessible")
            else:
                print_warning(f"{description} exists but may not be executable")
        else:
            print_error(f"{description} not found")
            all_good = False
    
    return all_good

def test_ollama_directory():
    """Test if Ollama directory structure is correct"""
    print_info("Testing Ollama directory structure...")
    
    home_dir = Path.home()
    ollama_dir = home_dir / ".ollama"
    models_dir = ollama_dir / "models"
    
    if not ollama_dir.exists():
        print_warning("~/.ollama directory does not exist")
        print_info("This is normal if Ollama hasn't been installed yet")
    else:
        print_success("~/.ollama directory exists")
        
        if models_dir.exists():
            print_success("~/.ollama/models directory exists")
            
            # List existing models
            models = list(models_dir.iterdir())
            if models:
                print_info(f"Found {len(models)} existing models:")
                for model in models[:5]:  # Show first 5
                    if model.is_dir():
                        size = sum(f.stat().st_size for f in model.rglob('*') if f.is_file())
                        print(f"  - {model.name} ({size / (1024*1024):.1f} MB)")
                if len(models) > 5:
                    print(f"  ... and {len(models) - 5} more")
            else:
                print_info("No models found in ~/.ollama/models")
        else:
            print_info("~/.ollama/models directory does not exist (will be created during installation)")
    
    return True

def test_network_configuration():
    """Test network configuration and port availability"""
    print_info("Testing network configuration...")
    
    import socket
    
    # Test if we can bind to common ports
    test_ports = [6881, 6882, 6891]  # BitTorrent ports
    
    for port in test_ports:
        try:
            with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
                s.bind(('localhost', port))
                s.close()
                print_success(f"Port {port} is available for BitTorrent")
        except OSError:
            print_warning(f"Port {port} is not available (may be in use)")
    
    return True

def run_integration_test(server_url):
    """Run a basic integration test"""
    print_info("Running integration test...")
    
    try:
        # Create a temporary test directory
        with tempfile.TemporaryDirectory() as temp_dir:
            test_file = Path(temp_dir) / "test.txt"
            test_file.write_text("This is a test file for BitTorrent testing")
            
            print_info(f"Created test file: {test_file}")
            
            # Test if we can access the server
            response = requests.get(f"{server_url}/api/models")
            if response.status_code == 200:
                models = response.json()
                print_success(f"Server API working, found {len(models)} models")
                
                if models:
                    # Test downloading a torrent file
                    model = models[0]
                    torrent_url = f"{server_url}/api/models/{model['name']}/torrent"
                    torrent_response = requests.get(torrent_url)
                    
                    if torrent_response.status_code == 200:
                        print_success(f"Torrent file download working for {model['name']}")
                    else:
                        print_warning(f"Torrent file download failed for {model['name']}")
                else:
                    print_info("No models available for testing")
            else:
                print_warning("Server API not responding correctly")
        
        return True
        
    except Exception as e:
        print_error(f"Integration test failed: {e}")
        return False

def main():
    """Main test function"""
    print_status("Ollama BitTorrent Lancache - System Test")
    print_info("Running comprehensive system tests...")
    
    # Configuration
    server_url = os.environ.get('TEST_SERVER_URL', 'http://localhost:8081')
    tracker_url = os.environ.get('TEST_TRACKER_URL', 'http://localhost:8080')
    
    print_info(f"Testing against server: {server_url}")
    print_info(f"Testing against tracker: {tracker_url}")
    
    # Run tests
    tests = [
        ("Python Dependencies", lambda: test_python_dependencies()),
        ("Installation Scripts", lambda: test_installation_scripts()),
        ("Ollama Directory", lambda: test_ollama_directory()),
        ("Network Configuration", lambda: test_network_configuration()),
        ("Tracker Connection", lambda: test_tracker_connection(tracker_url)),
        ("Server Connection", lambda: test_server_connection(server_url)),
        ("Seeder Script", lambda: test_seeder_script(server_url)),
        ("Integration Test", lambda: run_integration_test(server_url))
    ]
    
    results = []
    
    for test_name, test_func in tests:
        print(f"\n{'='*50}")
        print(f"Running: {test_name}")
        print('='*50)
        
        try:
            result = test_func()
            results.append((test_name, result))
        except Exception as e:
            print_error(f"Test {test_name} crashed: {e}")
            results.append((test_name, False))
    
    # Summary
    print(f"\n{'='*50}")
    print("TEST SUMMARY")
    print('='*50)
    
    passed = sum(1 for _, result in results if result)
    total = len(results)
    
    for test_name, result in results:
        status = "✅ PASS" if result else "❌ FAIL"
        print(f"{status}: {test_name}")
    
    print(f"\nOverall: {passed}/{total} tests passed")
    
    if passed == total:
        print_success("All tests passed! System is ready.")
        return 0
    else:
        print_warning(f"{total - passed} tests failed. Check the output above.")
        return 1

if __name__ == "__main__":
    sys.exit(main())
