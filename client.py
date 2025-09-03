#!/usr/bin/env python3
"""
Ollama BitTorrent Client - Download torrents to local directory
"""

import argparse
import os
import sys
import time
import requests
import libtorrent as lt

class OllamaClient:
    def __init__(self, tracker_url=None):
        """Initialize BitTorrent client"""
        self.session = lt.session()
        
        # Configure session settings
        settings = {
            'listen_interfaces': '0.0.0.0:6881',
            'enable_dht': False,  # Disable DHT for private trackers
            'enable_lsd': True,
            'enable_upnp': True,
            'enable_natpmp': True,
            'announce_to_all_trackers': True,
            'announce_to_all_tiers': True,
        }
        self.session.apply_settings(settings)
        
        # Add DHT routers (for public torrents)
        try:
            self.session.add_dht_router("router.bittorrent.com", 6881)
            self.session.add_dht_router("router.utorrent.com", 6881)
        except AttributeError:
            # DHT routers are automatically configured in newer versions
            pass
        
        print(f"🚀 Initialized BitTorrent client")
    
    def get_available_models(self, server_url):
        """Get list of available models from server"""
        try:
            response = requests.get(f"{server_url}/api/models")
            response.raise_for_status()
            return response.json()
        except Exception as e:
            print(f"❌ Error fetching models: {e}")
            return []
    
    def download_torrent_file(self, server_url, model_name, output_dir):
        """Download torrent file from server"""
        try:
            torrent_url = f"{server_url}/api/models/{model_name}/torrent"
            response = requests.get(torrent_url)
            response.raise_for_status()
            
            torrent_path = os.path.join(output_dir, f"{model_name.replace(':', '_')}.torrent")
            with open(torrent_path, 'wb') as f:
                f.write(response.content)
            
            print(f"✅ Downloaded torrent: {torrent_path}")
            return torrent_path
        except Exception as e:
            print(f"❌ Error downloading torrent: {e}")
            return None
    
    def download_model(self, server_url, model_name, output_dir):
        """Download a specific model to local directory"""
        print(f"📥 Downloading model: {model_name}")
        print(f"📁 Models will be saved to: {output_dir}")
        
        # Download torrent file
        torrent_path = self.download_torrent_file(server_url, model_name, output_dir)
        if not torrent_path:
            return False
        
        # Download the actual model files
        return self.download_from_torrent(torrent_path, output_dir)
    
    def download_from_torrent(self, torrent_path, output_dir):
        """Download files from torrent to specified directory"""
        try:
            print(f"🔍 Loading torrent file: {torrent_path}")
            
            info = lt.torrent_info(torrent_path)
            
            # Print tracker information
            trackers = list(info.trackers())
            if trackers:
                print(f"📡 Found {len(trackers)} tracker(s):")
                for tracker in trackers:
                    print(f"   - {tracker.url}")
            else:
                print("⚠️  No trackers found in torrent file")
            
            h = self.session.add_torrent({
                'ti': info,
                'save_path': output_dir
            })
            
            print(f"🚀 Started downloading to: {output_dir}")
            
            # Wait a moment for initial tracker contact
            time.sleep(2)
            
            # Monitor download progress
            start_time = time.time()
            last_peers = 0
            while not h.is_seed():
                s = h.status()
                elapsed = time.time() - start_time
                
                # Show connection status
                if s.num_peers != last_peers:
                    print(f"\n📡 Connected to {s.num_peers} peers, {s.num_seeds} seeds")
                    last_peers = s.num_peers
                
                # Show tracker status
                if hasattr(s, 'trackers') and s.trackers:
                    for tracker in s.trackers:
                        if tracker.url:
                            print(f"📡 Tracker {tracker.url}: {tracker.state}")
                
                if s.progress > 0:
                    eta = (elapsed / s.progress) * (1 - s.progress) if s.progress < 1 else 0
                    print(f"\r📊 Download: {s.progress*100:.1f}% complete | "
                          f"Speed: {s.download_rate/1024:.1f} KB/s | "
                          f"Peers: {s.num_peers} | "
                          f"ETA: {eta:.0f}s", end='', flush=True)
                else:
                    print(f"\r🔍 Connecting to peers... ({s.num_peers} peers found)", end='', flush=True)
                
                time.sleep(1)
            
            print(f"\n✅ Download completed to: {output_dir}")
            
            # Start seeding after download completes
            print("🌱 Starting to seed for other peers...")
            print("📡 Press Ctrl+C to stop seeding")
            
            # Monitor seeding progress
            start_time = time.time()
            try:
                while True:
                    s = h.status()
                    elapsed = time.time() - start_time
                    
                    # Show seeding status
                    print(f"\r🌱 Seeding: {s.upload_rate/1024:.1f} KB/s | "
                          f"Peers: {s.num_peers} | Seeds: {s.num_seeds} | "
                          f"Uptime: {elapsed:.0f}s", end='', flush=True)
                    
                    time.sleep(1)
            except KeyboardInterrupt:
                print("\n🛑 Stopping seeder...")
                return True
            
            return True
            
        except Exception as e:
            print(f"❌ Error downloading from torrent: {e}")
            return False
    
    def list_models(self, server_url):
        """List available models on server"""
        models = self.get_available_models(server_url)
        
        if not models:
            print("❌ No models found on server")
            return
        
        print(f"📋 Found {len(models)} models on server")
        print("\n📋 Available Models:")
        print("-" * 60)
        
        for model in models:
            size_mb = model['size'] / (1024 * 1024)
            print(f"📁 {model['name']:<30} {size_mb:>8.1f} MB")
        
        print("-" * 60)

def main():
    parser = argparse.ArgumentParser(
        description="Ollama BitTorrent Client - Download models to local directory",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # List available models
  python3 client.py --server http://192.168.1.100:8080 --list
  
  # Download specific model to local directory
  python3 client.py --server http://192.168.1.100:8080 --model phi3:mini --output ./downloads
  
  # Download from torrent file to local directory
  python3 client.py --file model.torrent --output ./downloads
  
  # Download with custom tracker
  python3 client.py --file model.torrent --output ./downloads --tracker http://192.168.1.100:8081
        """
    )
    
    # Main options
    parser.add_argument("--server", 
                       help="Server URL (e.g., http://192.168.1.100:8080)")
    parser.add_argument("--file", 
                       help="Torrent file to download")
    parser.add_argument("--output", "-o", 
                       help="Output directory for downloaded files (default: ./downloads)")
    parser.add_argument("--tracker", 
                       help="Tracker URL (default: http://localhost:8081)")
    parser.add_argument("--model", 
                       help="Specific model to download from server")
    parser.add_argument("--list", action="store_true", 
                       help="List available models on server")
    
    args = parser.parse_args()
    
    # Set defaults
    if not args.output:
        args.output = "./downloads"
    
    if not args.tracker:
        args.tracker = "http://localhost:8081"
    
    # Validate arguments
    if not any([args.file, args.list, args.model]):
        parser.error("Please specify an action: --file, --list, or --model")
    
    if args.model and not args.server:
        parser.error("--server is required with --model")
    
    if args.list and not args.server:
        parser.error("--server is required with --list")
    
    # Create output directory
    os.makedirs(args.output, exist_ok=True)
    
    try:
        client = OllamaClient(args.tracker)
        
        if args.list:
            client.list_models(args.server)
        elif args.file:
            client.download_from_torrent(args.file, args.output)
        elif args.model:
            client.download_model(args.server, args.model, args.output)
        
    except KeyboardInterrupt:
        print("\n🛑 Download cancelled by user")
    except Exception as e:
        print(f"❌ Fatal error: {e}")
        sys.exit(1)

if __name__ == "__main__":
    main()
