#!/usr/bin/env python3
"""
Ollama BitTorrent Seeder Script
Simple BitTorrent client for seeding torrent files

This script can be used to:
1. Seed torrent files directly (--file model.torrent)
2. Download models from the server
3. Seed local model directories
4. Test the BitTorrent functionality
"""

import argparse
import json
import os
import sys
import time
import requests
from pathlib import Path

try:
    import libtorrent as lt
except ImportError:
    print("❌ libtorrent not found. Please install it:")
    print("   pip install libtorrent")
    sys.exit(1)

class OllamaSeeder:
    def __init__(self, tracker_url=None):
        self.tracker_url = tracker_url or "http://localhost:8080"
        self.session = lt.session()
        
        # Configure session
        self.session.listen_on(6881, 6891)
        
        # Add DHT routers
        self.session.add_dht_router("router.bittorrent.com", 6881)
        self.session.add_dht_router("router.utorrent.com", 6881)
        
        # Add tracker if specified
        if tracker_url:
            self.session.add_tracker(lt.announce_entry(tracker_url))
        
        print(f"🚀 Initialized BitTorrent client")
        if tracker_url:
            print(f"📡 Using tracker: {tracker_url}")
    
    def seed_torrent_file(self, torrent_file):
        """Seed a torrent file directly"""
        if not os.path.exists(torrent_file):
            print(f"❌ Torrent file does not exist: {torrent_file}")
            return False
        
        try:
            print(f"🔍 Loading torrent file: {torrent_file}")
            info = lt.torrent_info(torrent_file)
            
            # Get the name from the torrent info
            torrent_name = info.name()
            print(f"📁 Torrent name: {torrent_name}")
            
            # Get total size
            total_size = info.total_size()
            print(f"📊 Total size: {total_size / (1024*1024):.1f} MB")
            
            # Get number of files
            num_files = info.num_files()
            print(f"📄 Number of files: {num_files}")
            
            # Get tracker URLs
            trackers = info.trackers()
            if trackers:
                print(f"📡 Trackers: {', '.join([t.url for t in trackers])}")
            
            # Add torrent to session
            h = self.session.add_torrent({
                'ti': info,
                'save_path': os.path.dirname(os.path.abspath(torrent_file))
            })
            
            print(f"🌱 Started seeding: {torrent_name}")
            print("📡 Press Ctrl+C to stop seeding")
            
            # Monitor seeding progress
            start_time = time.time()
            while True:
                s = h.status()
                elapsed = time.time() - start_time
                
                # Get peer info
                peers = s.num_peers
                seeds = s.num_seeds
                leeches = s.num_connections
                
                print(f"\r🌱 Seeding: {s.upload_rate/1024:.1f} KB/s | "
                      f"Peers: {peers} | Seeds: {seeds} | Connections: {leeches} | "
                      f"Uptime: {elapsed:.0f}s", end='', flush=True)
                
                time.sleep(1)
                
        except KeyboardInterrupt:
            print("\n🛑 Stopping seeder...")
            return True
        except Exception as e:
            print(f"❌ Error seeding torrent: {e}")
            return False
    
    def get_available_models(self, server_url):
        """Get list of available models from server"""
        try:
            response = requests.get(f"{server_url}/api/models")
            response.raise_for_status()
            models = response.json()
            print(f"📋 Found {len(models)} models on server")
            return models
        except Exception as e:
            print(f"❌ Error getting models: {e}")
            return []
    
    def create_torrent(self, model_path, output_path):
        """Create a torrent file for a model directory"""
        try:
            print(f"🔨 Creating torrent for: {model_path}")
            
            fs = lt.file_storage()
            lt.add_files(fs, model_path)
            
            t = lt.create_torrent(fs)
            t.add_tracker(self.tracker_url)
            t.set_creator("ollama-bt-lancache")
            
            # Set piece size to 1MB
            t.set_piece_length(1024 * 1024)
            
            # Calculate hashes
            print("📊 Calculating file hashes...")
            lt.set_piece_hashes(t, model_path)
            
            # Write torrent file
            with open(output_path, 'wb') as f:
                f.write(lt.bencode(t.generate()))
            
            print(f"✅ Torrent created: {output_path}")
            return True
        except Exception as e:
            print(f"❌ Error creating torrent: {e}")
            return False
    
    def download_model(self, server_url, model_name, download_all=False):
        """Download a specific model or all models"""
        models = self.get_available_models(server_url)
        
        if download_all:
            target_models = models
            print(f"📥 Downloading all {len(target_models)} models...")
        else:
            target_models = [m for m in models if m['name'] == model_name]
            if not target_models:
                print(f"❌ No models found matching: {model_name}")
                return
            print(f"📥 Downloading model: {model_name}")
        
        ollama_dir = Path.home() / ".ollama" / "models"
        ollama_dir.mkdir(parents=True, exist_ok=True)
        
        print(f"📁 Models will be saved to: {ollama_dir}")
        
        for model in target_models:
            print(f"\n🔄 Processing model: {model['name']}")
            
            # Download torrent file
            torrent_url = f"{server_url}/api/models/{model['name']}/torrent"
            torrent_path = ollama_dir / f"{model['name']}.torrent"
            
            try:
                print(f"📥 Downloading torrent file...")
                response = requests.get(torrent_url)
                response.raise_for_status()
                
                with open(torrent_path, 'wb') as f:
                    f.write(response.content)
                
                print(f"✅ Downloaded torrent: {torrent_path}")
                
                # Add torrent to session
                info = lt.torrent_info(str(torrent_path))
                h = self.session.add_torrent({
                    'ti': info,
                    'save_path': str(ollama_dir / model['name'])
                })
                
                print(f"🚀 Started downloading: {model['name']}")
                
                # Monitor download progress
                start_time = time.time()
                while not h.is_seed():
                    s = h.status()
                    elapsed = time.time() - start_time
                    
                    if s.progress > 0:
                        eta = (elapsed / s.progress) * (1 - s.progress) if s.progress < 1 else 0
                        print(f"\r📊 {model['name']}: {s.progress*100:.1f}% complete | "
                              f"Speed: {s.download_rate/1024:.1f} KB/s | "
                              f"ETA: {eta:.0f}s", end='', flush=True)
                    
                    time.sleep(1)
                
                print(f"\n✅ Downloaded: {model['name']}")
                
            except Exception as e:
                print(f"❌ Error downloading {model['name']}: {e}")
    
    def seed_model(self, model_path):
        """Seed a local model directory"""
        if not os.path.exists(model_path):
            print(f"❌ Model path does not exist: {model_path}")
            return
        
        print(f"🌱 Seeding model: {model_path}")
        
        torrent_path = f"{model_path}.torrent"
        
        if not os.path.exists(torrent_path):
            print(f"🔨 Creating torrent file for: {model_path}")
            if not self.create_torrent(model_path, torrent_path):
                return
        
        try:
            info = lt.torrent_info(torrent_path)
            h = self.session.add_torrent({
                'ti': info,
                'save_path': model_path
            })
            
            print(f"🌱 Now seeding: {model_path}")
            print("📡 Press Ctrl+C to stop seeding")
            
            start_time = time.time()
            while True:
                s = h.status()
                elapsed = time.time() - start_time
                
                print(f"\r🌱 Seeding: {s.upload_rate/1024:.1f} KB/s | "
                      f"Peers: {s.num_peers} | "
                      f"Uptime: {elapsed:.0f}s", end='', flush=True)
                
                time.sleep(1)
                
        except KeyboardInterrupt:
            print("\n🛑 Stopping seeder...")
        except Exception as e:
            print(f"❌ Error seeding: {e}")
    
    def list_models(self, server_url):
        """List available models on the server"""
        models = self.get_available_models(server_url)
        
        if not models:
            print("❌ No models found on server")
            return
        
        print(f"\n📋 Available Models ({len(models)}):")
        print("-" * 60)
        
        for model in models:
            size_mb = model.get('size', 0) / (1024 * 1024)
            print(f"📁 {model['name']:<30} {size_mb:>8.1f} MB")
        
        print("-" * 60)
    
    def status(self):
        """Show current session status"""
        print(f"\n📊 Session Status:")
        print(f"   Tracker: {self.tracker_url}")
        print(f"   Listen Ports: 6881-6891")
        
        torrents = self.session.get_torrents()
        if torrents:
            print(f"\n📥 Active Torrents ({len(torrents)}):")
            for h in torrents:
                s = h.status()
                name = h.get_torrent_info().name() if h.has_metadata() else "Unknown"
                print(f"   📁 {name}: {s.progress*100:.1f}% | "
                      f"↓{s.download_rate/1024:.1f} KB/s | "
                      f"↑{s.upload_rate/1024:.1f} KB/s")
        else:
            print("\n📥 No active torrents")

def main():
    parser = argparse.ArgumentParser(
        description="Ollama BitTorrent Seeder - Simple BitTorrent client for seeding torrent files",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Seed a torrent file directly (main use case)
  python3 seeder.py --file model.torrent
  
  # Seed with custom tracker
  python3 seeder.py --file model.torrent --tracker http://192.168.1.100:8080
  
  # Download all models from server
  python3 seeder.py --server http://192.168.1.100:8080 --download-all
  
  # Download specific model from server
  python3 seeder.py --server http://192.168.1.100:8080 --model llama2:7b
  
  # Seed local model directory
  python3 seeder.py --seed ~/.ollama/models/llama2:7b
  
  # List available models on server
  python3 seeder.py --server http://192.168.1.100:8080 --list
  
  # Show status
  python3 seeder.py --status
        """
    )
    
    # Main seeding option
    parser.add_argument("--file", 
                       help="Torrent file to seed (main use case)")
    
    # Server-based options
    parser.add_argument("--server", 
                       help="Server URL (e.g., http://192.168.1.100:8080)")
    parser.add_argument("--tracker", 
                       help="Tracker URL (default: http://localhost:8080)")
    parser.add_argument("--model", 
                       help="Specific model to download from server")
    parser.add_argument("--download-all", action="store_true", 
                       help="Download all available models from server")
    parser.add_argument("--seed", 
                       help="Seed a local model directory")
    parser.add_argument("--list", action="store_true", 
                       help="List available models on server")
    parser.add_argument("--status", action="store_true", 
                       help="Show current session status")
    
    args = parser.parse_args()
    
    # Validate arguments
    if not any([args.file, args.download_all, args.model, args.seed, args.list, args.status]):
        parser.error("Please specify an action: --file, --download-all, --model, --seed, --list, or --status")
    
    try:
        seeder = OllamaSeeder(args.tracker)
        
        if args.file:
            # Main use case: seed torrent file directly
            seeder.seed_torrent_file(args.file)
        elif args.list:
            if not args.server:
                parser.error("--server is required with --list")
            seeder.list_models(args.server)
        elif args.status:
            seeder.status()
        elif args.seed:
            seeder.seed_model(args.seed)
        elif args.download_all:
            if not args.server:
                parser.error("--server is required with --download-all")
            seeder.download_model(args.server, None, download_all=True)
        elif args.model:
            if not args.server:
                parser.error("--server is required with --model")
            seeder.download_model(args.server, args.model)
        
    except KeyboardInterrupt:
        print("\n🛑 Operation cancelled by user")
    except Exception as e:
        print(f"❌ Fatal error: {e}")
        sys.exit(1)

if __name__ == "__main__":
    main()
