#!/usr/bin/env python3
"""
Auto Seeder Script for Ollama BitTorrent Lancache

This script monitors the ~/.ollama/models directory for torrent files
and automatically starts seeding each one in a separate terminal.
"""

import os
import time
import subprocess
import argparse
import sys
from pathlib import Path
import json
import signal
import threading
from typing import Set, Dict

class AutoSeeder:
    def __init__(self, models_dir: str, tracker_url: str, check_interval: int = 10):
        self.models_dir = Path(models_dir).expanduser()
        self.tracker_url = tracker_url
        self.check_interval = check_interval
        self.running_seeders: Dict[str, subprocess.Popen] = {}
        self.monitored_torrents: Set[str] = set()
        self.running = True
        
        # Setup signal handlers for graceful shutdown
        signal.signal(signal.SIGINT, self._signal_handler)
        signal.signal(signal.SIGTERM, self._signal_handler)
        
        print(f"🚀 Auto Seeder initialized")
        print(f"📁 Monitoring directory: {self.models_dir}")
        print(f"📡 Tracker URL: {self.tracker_url}")
        print(f"⏱️  Check interval: {self.check_interval} seconds")
    
    def _signal_handler(self, signum, frame):
        """Handle shutdown signals gracefully"""
        print(f"\n🛑 Received signal {signum}, shutting down...")
        self.running = False
        self.stop_all_seeders()
        sys.exit(0)
    
    def find_torrent_files(self) -> Set[str]:
        """Find all torrent files in the models directory"""
        torrent_files = set()
        
        if not self.models_dir.exists():
            return torrent_files
        
        # Look for .torrent files in the models directory
        for torrent_file in self.models_dir.glob("*.torrent"):
            torrent_files.add(str(torrent_file))
        
        return torrent_files
    
    def get_model_name_from_torrent(self, torrent_file: str) -> str:
        """Extract model name from torrent filename"""
        filename = Path(torrent_file).stem
        # Convert underscores back to colons for model names
        model_name = filename.replace("_", ":")
        return model_name
    
    def start_seeder(self, torrent_file: str) -> bool:
        """Start a seeder process for a torrent file"""
        model_name = self.get_model_name_from_torrent(torrent_file)
        
        if torrent_file in self.running_seeders:
            print(f"⚠️  Seeder already running for {model_name}")
            return False
        
        try:
            # Create the command to run in a new terminal
            script_dir = Path(__file__).parent.absolute()
            venv_path = script_dir / "venv" / "bin" / "activate"
            seeder_script = script_dir / "seeder.py"
            
            # Build the command (don't override tracker URL - use the one in the torrent file)
            cmd = [
                "osascript", "-e",
                f'tell application "Terminal" to do script "cd {script_dir} && echo \\"🌱 Starting Seeder for {model_name}...\\" && source {venv_path} && python3 {seeder_script} --file {torrent_file}"'
            ]
            
            print(f"🌱 Starting seeder for {model_name}...")
            print(f"📁 Torrent file: {torrent_file}")
            
            # Execute the command
            process = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            self.running_seeders[torrent_file] = process
            
            print(f"✅ Seeder started for {model_name}")
            
            # Wait a moment for the seeder to start
            time.sleep(2)
            
            return True
            
        except Exception as e:
            print(f"❌ Failed to start seeder for {model_name}: {e}")
            return False
    
    def stop_seeder(self, torrent_file: str):
        """Stop a specific seeder process"""
        if torrent_file in self.running_seeders:
            try:
                process = self.running_seeders[torrent_file]
                process.terminate()
                del self.running_seeders[torrent_file]
                model_name = self.get_model_name_from_torrent(torrent_file)
                print(f"🛑 Stopped seeder for {model_name}")
            except Exception as e:
                print(f"❌ Error stopping seeder for {torrent_file}: {e}")
    
    def stop_all_seeders(self):
        """Stop all running seeder processes"""
        print("🛑 Stopping all seeders...")
        for torrent_file in list(self.running_seeders.keys()):
            self.stop_seeder(torrent_file)
    
    def check_seeder_status(self):
        """Check if seeder processes are still running"""
        dead_seeders = []
        
        for torrent_file, process in self.running_seeders.items():
            if process.poll() is not None:
                # The osascript process has terminated, but check if the actual seeder is still running
                model_name = self.get_model_name_from_torrent(torrent_file)
                
                # Check if there's still a seeder.py process running for this torrent
                try:
                    import subprocess
                    result = subprocess.run(['pgrep', '-f', f'seeder.py.*{os.path.basename(torrent_file)}'], 
                                          capture_output=True, text=True)
                    if result.returncode == 0 and result.stdout.strip():
                        # The actual seeder is still running, just the osascript process ended
                        print(f"✅ Seeder for {model_name} is running (osascript process ended)")
                        continue
                except Exception:
                    pass
                
                # No seeder process found, mark as dead
                dead_seeders.append(torrent_file)
        
        # Remove dead seeders
        for torrent_file in dead_seeders:
            model_name = self.get_model_name_from_torrent(torrent_file)
            print(f"⚠️  Seeder for {model_name} has stopped")
            del self.running_seeders[torrent_file]
    
    def monitor(self):
        """Main monitoring loop"""
        print(f"🔍 Starting monitoring loop...")
        print(f"📊 Press Ctrl+C to stop monitoring")
        
        while self.running:
            try:
                # Check for new torrent files
                current_torrents = self.find_torrent_files()
                
                # Start seeders for new torrent files
                for torrent_file in current_torrents:
                    if torrent_file not in self.monitored_torrents:
                        self.start_seeder(torrent_file)
                        self.monitored_torrents.add(torrent_file)
                
                # Check if any torrent files were removed
                removed_torrents = self.monitored_torrents - current_torrents
                for torrent_file in removed_torrents:
                    model_name = self.get_model_name_from_torrent(torrent_file)
                    print(f"📁 Torrent file removed: {model_name}")
                    self.stop_seeder(torrent_file)
                    self.monitored_torrents.remove(torrent_file)
                
                # Check seeder status
                self.check_seeder_status()
                
                # Print status
                if self.running_seeders:
                    print(f"📊 Active seeders: {len(self.running_seeders)}")
                    for torrent_file in self.running_seeders.keys():
                        model_name = self.get_model_name_from_torrent(torrent_file)
                        print(f"   🌱 {model_name}")
                
                # Wait before next check
                time.sleep(self.check_interval)
                
            except KeyboardInterrupt:
                break
            except Exception as e:
                print(f"❌ Error in monitoring loop: {e}")
                time.sleep(self.check_interval)
        
        print("🛑 Monitoring stopped")
        self.stop_all_seeders()
    
    def start_all_existing(self):
        """Start seeders for all existing torrent files"""
        print("🔍 Checking for existing torrent files...")
        torrent_files = self.find_torrent_files()
        
        if not torrent_files:
            print("📁 No torrent files found")
            return
        
        print(f"📁 Found {len(torrent_files)} torrent files:")
        for torrent_file in torrent_files:
            model_name = self.get_model_name_from_torrent(torrent_file)
            print(f"   📄 {model_name}")
        
        print("🌱 Starting seeders for all existing torrents...")
        for torrent_file in torrent_files:
            self.start_seeder(torrent_file)
            self.monitored_torrents.add(torrent_file)
            time.sleep(1)  # Small delay between starting seeders
    
    def status(self):
        """Show current status"""
        print("📊 Auto Seeder Status:")
        print(f"📁 Monitoring directory: {self.models_dir}")
        print(f"📡 Tracker URL: {self.tracker_url}")
        print(f"⏱️  Check interval: {self.check_interval} seconds")
        print(f"🔍 Monitored torrents: {len(self.monitored_torrents)}")
        print(f"🌱 Active seeders: {len(self.running_seeders)}")
        
        if self.running_seeders:
            print("\n🌱 Active Seeders:")
            for torrent_file in self.running_seeders.keys():
                model_name = self.get_model_name_from_torrent(torrent_file)
                print(f"   📄 {model_name}")

def main():
    parser = argparse.ArgumentParser(
        description="Auto Seeder for Ollama BitTorrent Lancache",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Start monitoring and auto-seed all torrents
  python3 auto_seeder.py --tracker http://localhost:8081

  # Start monitoring with custom models directory
  python3 auto_seeder.py --models-dir ~/.ollama/models --tracker http://localhost:8081

  # Start seeders for existing torrents only (no monitoring)
  python3 auto_seeder.py --tracker http://localhost:8081 --start-existing-only

  # Check status
  python3 auto_seeder.py --tracker http://localhost:8081 --status
        """
    )
    
    parser.add_argument("--models-dir", default="~/.ollama/models",
                       help="Models directory to monitor (default: ~/.ollama/models)")
    parser.add_argument("--tracker", required=True,
                       help="BitTorrent tracker URL")
    parser.add_argument("--check-interval", type=int, default=10,
                       help="Check interval in seconds (default: 10)")
    parser.add_argument("--start-existing-only", action="store_true",
                       help="Start seeders for existing torrents only, don't monitor")
    parser.add_argument("--status", action="store_true",
                       help="Show current status and exit")
    
    args = parser.parse_args()
    
    try:
        auto_seeder = AutoSeeder(
            models_dir=args.models_dir,
            tracker_url=args.tracker,
            check_interval=args.check_interval
        )
        
        if args.status:
            auto_seeder.status()
            return
        
        if args.start_existing_only:
            auto_seeder.start_all_existing()
            print("✅ Started seeders for all existing torrents")
            print("📊 Press Ctrl+C to stop all seeders")
            
            # Keep running to maintain seeders
            try:
                while True:
                    auto_seeder.check_seeder_status()
                    time.sleep(5)
            except KeyboardInterrupt:
                print("\n🛑 Stopping all seeders...")
                auto_seeder.stop_all_seeders()
        else:
            # Start existing seeders first
            auto_seeder.start_all_existing()
            
            # Then start monitoring
            auto_seeder.monitor()
    
    except KeyboardInterrupt:
        print("\n🛑 Interrupted by user")
    except Exception as e:
        print(f"❌ Fatal error: {e}")
        sys.exit(1)

if __name__ == "__main__":
    main()
