package main

import (
	"encoding/json"
	"fmt"
	"html/template"
	"net"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/gorilla/mux"
	"github.com/mitchellh/go-homedir"
	"github.com/sirupsen/logrus"
	"github.com/spf13/cobra"
	"github.com/spf13/viper"
)

type Model struct {
	Name         string    `json:"name"`
	Size         int64     `json:"size"`
	Path         string    `json:"path"`
	TorrentFile  string    `json:"torrent_file"`
	CreatedAt    time.Time `json:"created_at"`
	InfoHash     string    `json:"info_hash"`
}

type Server struct {
	models     []Model
	modelsDir  string
	serverIP   string
	port       string
	trackerURL string
	logger     *logrus.Logger
}

var (
	cfgFile string
	port    string
	logger  = logrus.New()
)

func main() {
	cmd := &cobra.Command{
		Use:   "ollama-bt-lancache",
		Short: "Ollama BitTorrent Lancache Server",
		Long:  `A BitTorrent-based server for distributing Ollama model blobs`,
		Run:   run,
	}

	cmd.PersistentFlags().StringVar(&cfgFile, "config", "", "config file (default is $HOME/.ollama-bt-lancache.yaml)")
	cmd.PersistentFlags().StringVar(&port, "port", "8080", "port to listen on")
	cmd.PersistentFlags().StringVarP(&port, "port", "p", "8080", "port to listen on")

	viper.BindPFlag("port", cmd.PersistentFlags().Lookup("port"))

	if err := cmd.Execute(); err != nil {
		fmt.Println(err)
		os.Exit(1)
	}
}

func run(cmd *cobra.Command, args []string) {
	// Initialize configuration
	initConfig()

	// Get models directory
	homeDir, err := homedir.Dir()
	if err != nil {
		logger.Fatal("Failed to get home directory:", err)
	}

	modelsDir := filepath.Join(homeDir, ".ollama", "models")
	if !viper.IsSet("models_dir") {
		viper.Set("models_dir", modelsDir)
	}

	// Get local IP address
	localIP, err := getLocalIP()
	if err != nil {
		logger.Fatal("Failed to get local IP:", err)
	}

	// Initialize server
	server := &Server{
		models:     []Model{},
		modelsDir:  viper.GetString("models_dir"),
		serverIP:   localIP,
		port:       viper.GetString("port"),
		trackerURL: viper.GetString("tracker_url"),
		logger:     logger,
	}

	// Discover models
	if err := server.discoverModels(); err != nil {
		logger.Fatal("Failed to discover models:", err)
	}

	// Start HTTP server
	server.startHTTPServer()
}

func initConfig() {
	if cfgFile != "" {
		viper.SetConfigFile(cfgFile)
	} else {
		home, err := homedir.Dir()
		if err != nil {
			fmt.Println(err)
			os.Exit(1)
		}

		viper.AddConfigPath(home)
		viper.SetConfigType("yaml")
		viper.SetConfigName(".ollama-bt-lancache")
	}

	viper.AutomaticEnv()

	if err := viper.ReadInConfig(); err == nil {
		fmt.Println("Using config file:", viper.ConfigFileUsed())
	}
}

func getLocalIP() (string, error) {
	conn, err := net.Dial("udp", "8.8.8.8:80")
	if err != nil {
		return "", err
	}
	defer conn.Close()

	localAddr := conn.LocalAddr().(*net.UDPAddr)
	return localAddr.IP.String(), nil
}

func (s *Server) discoverModels() error {
	s.logger.Infof("Discovering models in: %s", s.modelsDir)

	entries, err := os.ReadDir(s.modelsDir)
	if err != nil {
		return fmt.Errorf("failed to read models directory: %w", err)
	}

	for _, entry := range entries {
		if entry.IsDir() {
			modelPath := filepath.Join(s.modelsDir, entry.Name())
			model := Model{
				Name:      entry.Name(),
				Path:      modelPath,
				CreatedAt: time.Now(),
			}

			// Get model size
			if size, err := getDirSize(modelPath); err == nil {
				model.Size = size
			}

			// Generate torrent file
			if torrentFile, err := s.generateTorrentFile(model); err == nil {
				model.TorrentFile = torrentFile
			}

			s.models = append(s.models, model)
			s.logger.Infof("Discovered model: %s (Size: %d bytes)", model.Name, model.Size)
		}
	}

	return nil
}

func getDirSize(path string) (int64, error) {
	var size int64
	err := filepath.Walk(path, func(_ string, info os.FileInfo, err error) error {
		if err != nil {
			return err
		}
		if !info.IsDir() {
			size += info.Size()
		}
		return nil
	})
	return size, err
}

func (s *Server) generateTorrentFile(model Model) (string, error) {
	// For now, create a simple torrent file path
	// In a real implementation, you would use a proper BitTorrent library
	torrentFile := fmt.Sprintf("%s.torrent", model.Name)
	return torrentFile, nil
}

func (s *Server) startHTTPServer() {
	r := mux.NewRouter()

	// API routes
	r.HandleFunc("/api/models", s.getModels).Methods("GET")
	r.HandleFunc("/api/models/{name}/torrent", s.getTorrentFile).Methods("GET")

	// Static files
	r.HandleFunc("/install.ps1", s.servePowerShellScript).Methods("GET")
	r.HandleFunc("/install.sh", s.serveBashScript).Methods("GET")
	r.HandleFunc("/seeder.py", s.serveSeederScript).Methods("GET")

	// Web interface
	r.HandleFunc("/", s.serveWebInterface).Methods("GET")

	s.logger.Infof("Starting server on %s:%s", s.serverIP, s.port)
	s.logger.Fatal(http.ListenAndServe(":"+s.port, r))
}

func (s *Server) getModels(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(s.models)
}

func (s *Server) getTorrentFile(w http.ResponseWriter, r *http.Request) {
	vars := mux.Vars(r)
	modelName := vars["name"]

	for _, model := range s.models {
		if model.Name == modelName {
			// In a real implementation, you would serve the actual torrent file
			w.Header().Set("Content-Type", "application/x-bittorrent")
			w.Header().Set("Content-Disposition", fmt.Sprintf("attachment; filename=\"%s.torrent\"", modelName))
			w.Write([]byte(fmt.Sprintf("d8:announce%d:%s4:info...", len(s.trackerURL), s.trackerURL)))
			return
		}
	}

	http.NotFound(w, r)
}

func (s *Server) servePowerShellScript(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "text/plain")
	w.Header().Set("Content-Disposition", "attachment; filename=\"install.ps1\"")

	script := generatePowerShellScript(s.serverIP, s.port)
	w.Write([]byte(script))
}

func (s *Server) serveBashScript(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "text/plain")
	w.Header().Set("Content-Disposition", "attachment; filename=\"install.sh\"")

	script := generateBashScript(s.serverIP, s.port)
	w.Write([]byte(script))
}

func (s *Server) serveSeederScript(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "text/plain")
	w.Header().Set("Content-Disposition", "attachment; filename=\"seeder.py\"")

	script := generateSeederScript(s.serverIP, s.port, s.trackerURL)
	w.Write([]byte(script))
}

func (s *Server) serveWebInterface(w http.ResponseWriter, r *http.Request) {
	tmpl := `
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Ollama BitTorrent Lancache</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 40px; background-color: #f5f5f5; }
        .container { max-width: 1200px; margin: 0 auto; background: white; padding: 20px; border-radius: 8px; box-shadow: 0 2px 10px rgba(0,0,0,0.1); }
        h1 { color: #333; text-align: center; }
        .model-grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(300px, 1fr)); gap: 20px; margin-top: 30px; }
        .model-card { border: 1px solid #ddd; border-radius: 8px; padding: 20px; background: #fafafa; }
        .model-name { font-size: 18px; font-weight: bold; color: #333; margin-bottom: 10px; }
        .model-size { color: #666; margin-bottom: 10px; }
        .download-btn { background: #007bff; color: white; padding: 10px 20px; border: none; border-radius: 4px; cursor: pointer; text-decoration: none; display: inline-block; }
        .download-btn:hover { background: #0056b3; }
        .install-scripts { margin-top: 30px; padding: 20px; background: #e9ecef; border-radius: 8px; }
        .script-section { margin-bottom: 20px; }
        .script-title { font-weight: bold; margin-bottom: 10px; }
        .script-code { background: #f8f9fa; padding: 15px; border-radius: 4px; font-family: monospace; white-space: pre-wrap; }
    </style>
</head>
<body>
    <div class="container">
        <h1>🚀 Ollama BitTorrent Lancache</h1>
        <p style="text-align: center; color: #666;">Efficiently distribute Ollama models using BitTorrent</p>
        
        <div class="model-grid">
            {{range .Models}}
            <div class="model-card">
                <div class="model-name">{{.Name}}</div>
                <div class="model-size">Size: {{formatSize .Size}}</div>
                <a href="/api/models/{{.Name}}/torrent" class="download-btn">Download Torrent</a>
            </div>
            {{end}}
        </div>

        <div class="install-scripts">
            <h2>Installation Scripts</h2>
            
            <div class="script-section">
                <div class="script-title">Windows (PowerShell)</div>
                <div class="script-code">Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
Invoke-WebRequest -Uri "http://{{.ServerIP}}:{{.Port}}/install.ps1" -OutFile "install.ps1"
.\install.ps1</div>
            </div>
            
            <div class="script-section">
                <div class="script-title">Linux/macOS (Bash)</div>
                <div class="script-code">curl -sSL "http://{{.ServerIP}}:{{.Port}}/install.sh" | bash</div>
            </div>
            
            <div class="script-section">
                <div class="script-title">Python Seeder Script</div>
                <div class="script-code">curl -sSL "http://{{.ServerIP}}:{{.Port}}/seeder.py" -o seeder.py
python3 seeder.py --help</div>
            </div>
        </div>
    </div>

    <script>
        function formatSize(bytes) {
            if (bytes === 0) return '0 Bytes';
            const k = 1024;
            const sizes = ['Bytes', 'KB', 'MB', 'GB', 'TB'];
            const i = Math.floor(Math.log(bytes) / Math.log(k));
            return parseFloat((bytes / Math.pow(k, i)).toFixed(2)) + ' ' + sizes[i];
        }
        
        // Format sizes on page load
        document.addEventListener('DOMContentLoaded', function() {
            const sizeElements = document.querySelectorAll('.model-size');
            sizeElements.forEach(function(el) {
                const text = el.textContent;
                const match = text.match(/Size: (\d+)/);
                if (match) {
                    const bytes = parseInt(match[1]);
                    el.textContent = 'Size: ' + formatSize(bytes);
                }
            });
        });
    </script>
</body>
</html>`

	tmplData := struct {
		Models    []Model
		ServerIP  string
		Port      string
	}{
		Models:    s.models,
		ServerIP:  s.serverIP,
		Port:      s.port,
	}

	t, err := template.New("web").Parse(tmpl)
	if err != nil {
		http.Error(w, "Internal Server Error", http.StatusInternalServerError)
		return
	}

	t.Execute(w, tmplData)
}

func generatePowerShellScript(serverIP, port string) string {
	return fmt.Sprintf(`# Ollama BitTorrent Lancache Installer for Windows
# Run this script as Administrator

param(
    [string]$Model = "all"
)

Write-Host "🚀 Installing Ollama BitTorrent Lancache..." -ForegroundColor Green

# Check if Python is installed
try {
    $pythonVersion = python --version 2>&1
    Write-Host "Python found: $pythonVersion" -ForegroundColor Green
} catch {
    Write-Host "❌ Python not found. Please install Python 3.8+ from https://python.org" -ForegroundColor Red
    exit 1
}

# Create virtual environment
$venvPath = "$env:USERPROFILE\.ollama-bt-venv"
if (Test-Path $venvPath) {
    Write-Host "Virtual environment already exists at $venvPath" -ForegroundColor Yellow
} else {
    Write-Host "Creating virtual environment..." -ForegroundColor Yellow
    python -m venv $venvPath
}

# Activate virtual environment
Write-Host "Activating virtual environment..." -ForegroundColor Yellow
& "$venvPath\Scripts\Activate.ps1"

# Install required packages
Write-Host "Installing required packages..." -ForegroundColor Yellow
pip install --upgrade pip
pip install libtorrent requests

# Download seeder script
$seederUrl = "http://%s:%s/seeder.py"
$seederPath = "$env:USERPROFILE\seeder.py"
Write-Host "Downloading seeder script..." -ForegroundColor Yellow
Invoke-WebRequest -Uri $seederUrl -OutFile $seederPath

# Download models based on parameter
if ($Model -eq "all") {
    Write-Host "Downloading all available models..." -ForegroundColor Green
    python $seederPath --server http://%s:%s --download-all
} else {
    Write-Host "Downloading model: $Model" -ForegroundColor Green
    python $seederPath --server http://%s:%s --model $Model
}

Write-Host "✅ Installation complete!" -ForegroundColor Green
Write-Host "Models downloaded to: $env:USERPROFILE\.ollama\models" -ForegroundColor Green
`, serverIP, port, serverIP, port, serverIP, port)
}

func generateBashScript(serverIP, port string) string {
	return fmt.Sprintf(`#!/bin/bash
# Ollama BitTorrent Lancache Installer for Linux/macOS

set -e

MODEL=${1:-"all"}
SERVER_URL="http://%s:%s"

echo "🚀 Installing Ollama BitTorrent Lancache..."

# Check if Python is installed
if ! command -v python3 &> /dev/null; then
    echo "❌ Python 3 not found. Please install Python 3.8+"
    exit 1
fi

PYTHON_VERSION=$(python3 --version 2>&1)
echo "Python found: $PYTHON_VERSION"

# Create virtual environment
VENV_PATH="$HOME/.ollama-bt-venv"
if [ -d "$VENV_PATH" ]; then
    echo "Virtual environment already exists at $VENV_PATH"
else
    echo "Creating virtual environment..."
    python3 -m venv "$VENV_PATH"
fi

# Activate virtual environment
echo "Activating virtual environment..."
source "$VENV_PATH/bin/activate"

# Install required packages
echo "Installing required packages..."
pip install --upgrade pip
pip install libtorrent requests

# Download seeder script
SEEDER_URL="$SERVER_URL/seeder.py"
SEEDER_PATH="$HOME/seeder.py"
echo "Downloading seeder script..."
curl -sSL "$SEEDER_URL" -o "$SEEDER_PATH"

# Download models based on parameter
if [ "$MODEL" = "all" ]; then
    echo "Downloading all available models..."
    python3 "$SEEDER_PATH" --server "$SERVER_URL" --download-all
else
    echo "Downloading model: $MODEL"
    python3 "$SEEDER_PATH" --server "$SERVER_URL" --model "$MODEL"
fi

echo "✅ Installation complete!"
echo "Models downloaded to: $HOME/.ollama/models"
`, serverIP, port)
}

func generateSeederScript(serverIP, port, trackerURL string) string {
	return fmt.Sprintf(`#!/usr/bin/env python3
"""
Ollama BitTorrent Seeder Script
Downloads and seeds Ollama models using BitTorrent
"""

import argparse
import json
import os
import sys
import time
import requests
import libtorrent as lt
from pathlib import Path

class OllamaSeeder:
    def __init__(self, server_url, tracker_url=None):
        self.server_url = server_url.rstrip('/')
        self.tracker_url = tracker_url or "http://localhost:8080"
        self.session = lt.session()
        self.session.listen_on(6881, 6891)
        
        # Add tracker
        self.session.add_dht_router("router.bittorrent.com", 6881)
        self.session.add_dht_router("router.utorrent.com", 6881)
        
        if tracker_url:
            self.session.add_tracker(lt.announce_entry(tracker_url))
    
    def get_available_models(self):
        """Get list of available models from server"""
        try:
            response = requests.get(f"{self.server_url}/api/models")
            response.raise_for_status()
            return response.json()
        except Exception as e:
            print(f"Error getting models: {e}")
            return []
    
    def create_torrent(self, model_path, output_path):
        """Create a torrent file for a model directory"""
        try:
            fs = lt.file_storage()
            lt.add_files(fs, model_path)
            
            t = lt.create_torrent(fs)
            t.add_tracker(self.tracker_url)
            t.set_creator("ollama-bt-lancache")
            
            # Set piece size to 1MB
            t.set_piece_length(1024 * 1024)
            
            # Calculate hashes
            lt.set_piece_hashes(t, model_path)
            
            # Write torrent file
            with open(output_path, 'wb') as f:
                f.write(lt.bencode(t.generate()))
            
            return True
        except Exception as e:
            print(f"Error creating torrent: {e}")
            return False
    
    def download_model(self, model_name, download_all=False):
        """Download a specific model or all models"""
        models = self.get_available_models()
        
        if download_all:
            target_models = models
        else:
            target_models = [m for m in models if m['name'] == model_name]
        
        if not target_models:
            print(f"No models found matching: {model_name}")
            return
        
        ollama_dir = Path.home() / ".ollama" / "models"
        ollama_dir.mkdir(parents=True, exist_ok=True)
        
        for model in target_models:
            print(f"Processing model: {model['name']}")
            
            # Download torrent file
            torrent_url = f"{self.server_url}/api/models/{model['name']}/torrent"
            torrent_path = ollama_dir / f"{model['name']}.torrent"
            
            try:
                response = requests.get(torrent_url)
                response.raise_for_status()
                
                with open(torrent_path, 'wb') as f:
                    f.write(response.content)
                
                print(f"Downloaded torrent: {torrent_path}")
                
                # Add torrent to session
                info = lt.torrent_info(str(torrent_path))
                h = self.session.add_torrent({
                    'ti': info,
                    'save_path': str(ollama_dir / model['name'])
                })
                
                print(f"Started downloading: {model['name']}")
                
                # Monitor download progress
                while not h.is_seed():
                    s = h.status()
                    print(f"\\r{model['name']}: {s.progress*100:.1f}%% complete", end='', flush=True)
                    time.sleep(1)
                
                print(f"\\n✅ Downloaded: {model['name']}")
                
            except Exception as e:
                print(f"Error downloading {model['name']}: {e}")
    
    def seed_model(self, model_path):
        """Seed a local model directory"""
        if not os.path.exists(model_path):
            print(f"Model path does not exist: {model_path}")
            return
        
        torrent_path = f"{model_path}.torrent"
        
        if not os.path.exists(torrent_path):
            print(f"Creating torrent file for: {model_path}")
            if not self.create_torrent(model_path, torrent_path):
                return
        
        try:
            info = lt.torrent_info(torrent_path)
            h = self.session.add_torrent({
                'ti': info,
                'save_path': model_path
            })
            
            print(f"Seeding: {model_path}")
            print("Press Ctrl+C to stop seeding")
            
            while True:
                s = h.status()
                print(f"\\rSeeding: {s.upload_rate/1024:.1f} KB/s", end='', flush=True)
                time.sleep(1)
                
        except KeyboardInterrupt:
            print("\\nStopping seeder...")
        except Exception as e:
            print(f"Error seeding: {e}")

def main():
    parser = argparse.ArgumentParser(description="Ollama BitTorrent Seeder")
    parser.add_argument("--server", required=True, help="Server URL")
    parser.add_argument("--tracker", help="Tracker URL")
    parser.add_argument("--model", help="Specific model to download")
    parser.add_argument("--download-all", action="store_true", help="Download all available models")
    parser.add_argument("--seed", help="Seed a local model directory")
    
    args = parser.parse_args()
    
    seeder = OllamaSeeder(args.server, args.tracker)
    
    if args.seed:
        seeder.seed_model(args.seed)
    elif args.download_all:
        seeder.download_model(None, download_all=True)
    elif args.model:
        seeder.download_model(args.model)
    else:
        print("Please specify --model, --download-all, or --seed")
        sys.exit(1)

if __name__ == "__main__":
    main()
`)
}

func formatSize(bytes int64) string {
	if bytes == 0 {
		return "0 Bytes"
	}
	
	const k = 1024
	sizes := []string{"Bytes", "KB", "MB", "GB", "TB"}
	i := 0
	for bytes >= k && i < len(sizes)-1 {
		bytes /= k
		i++
	}
	
	return fmt.Sprintf("%.2f %s", float64(bytes), sizes[i])
}
