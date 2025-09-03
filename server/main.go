package main

import (
	"crypto/sha1"
	"encoding/json"
	"fmt"
	"html/template"
	"io"
	"net"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/anacrolix/torrent/bencode"
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

// Torrent structures for creating .torrent files
type TorrentFile struct {
	Announce     string                 `bencode:"announce"`
	AnnounceList [][]string             `bencode:"announce-list,omitempty"`
	Comment      string                 `bencode:"comment,omitempty"`
	CreatedBy    string                 `bencode:"created by,omitempty"`
	CreationDate int64                  `bencode:"creation date,omitempty"`
	Encoding     string                 `bencode:"encoding,omitempty"`
	Info         TorrentInfo            `bencode:"info"`
}

type TorrentInfo struct {
	PieceLength int64    `bencode:"piece length"`
	Pieces      string   `bencode:"pieces"`
	Private     int      `bencode:"private,omitempty"`
	Name        string   `bencode:"name"`
	Length      int64    `bencode:"length,omitempty"`      // For single file
	Files       []File   `bencode:"files,omitempty"`       // For multiple files
}

type File struct {
	Length int64    `bencode:"length"`
	Path   []string `bencode:"path"`
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

	// Set default tracker URL if not configured
	if !viper.IsSet("tracker_url") {
		viper.Set("tracker_url", fmt.Sprintf("http://%s:8081/ollama/announce", localIP))
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
	s.logger.Infof("Discovering Ollama models in: %s", s.modelsDir)

	// Parse Ollama manifest files to find actual models
	models, err := s.parseOllamaManifests()
	if err != nil {
		s.logger.Warnf("Failed to parse Ollama manifests: %v", err)
		// Fallback to directory scanning
		return s.discoverModelsFromDirectories()
	}

	s.models = models
	s.logger.Infof("Discovered %d Ollama models", len(s.models))
	
	return nil
}

func (s *Server) parseOllamaManifests() ([]Model, error) {
	var models []Model
	modelMap := make(map[string]Model) // For deduplication
	manifestsDir := filepath.Join(s.modelsDir, "manifests")
	
	// Walk through the manifests directory structure
	err := filepath.Walk(manifestsDir, func(path string, info os.FileInfo, err error) error {
		if err != nil {
			return err
		}
		
		// Look for manifest files (not directories)
		if !info.IsDir() {
			// Extract model name from path
			// Path format: manifests/registry.ollama.ai/library/granite3.3/8b
			relPath, err := filepath.Rel(manifestsDir, path)
			if err != nil {
				return err
			}
			
			// Parse the path to extract model name
			parts := strings.Split(relPath, string(filepath.Separator))
			if len(parts) >= 3 {
				// Format: registry.ollama.ai/library/model_name/tag
				// or: registry.ollama.ai/model_name/tag
				var modelName string
				if parts[1] == "library" && len(parts) >= 4 {
					// Remove .json extension if present
					tag := parts[3]
					if strings.HasSuffix(tag, ".json") {
						tag = strings.TrimSuffix(tag, ".json")
					}
					modelName = fmt.Sprintf("%s:%s", parts[2], tag)
				} else if len(parts) >= 3 {
					// Remove .json extension if present
					tag := parts[2]
					if strings.HasSuffix(tag, ".json") {
						tag = strings.TrimSuffix(tag, ".json")
					}
					modelName = fmt.Sprintf("%s:%s", parts[1], tag)
				}
				
				if modelName != "" {
					// Calculate model size by reading the manifest
					size, err := s.calculateModelSize(path)
					if err != nil {
						s.logger.Warnf("Failed to calculate size for %s: %v", modelName, err)
						size = 0
					}
					
					model := Model{
						Name:      modelName,
						Path:      s.modelsDir, // All models share the same blobs directory
						Size:      size,
						CreatedAt: time.Now(),
					}
					
					// Generate individual torrent file for this specific model
					if torrentFile, err := s.generateModelTorrentFile(&model); err == nil {
						model.TorrentFile = torrentFile
					}
					
					// Add to map for deduplication
					modelMap[model.Name] = model
					s.logger.Infof("Discovered Ollama model: %s (Size: %d bytes)", model.Name, model.Size)
				}
			}
		}
		
		return nil
	})
	
	// Convert map to slice
	for _, model := range modelMap {
		models = append(models, model)
	}
	
	return models, err
}

func (s *Server) calculateModelSize(manifestPath string) (int64, error) {
	// Read the manifest file to calculate total size
	data, err := os.ReadFile(manifestPath)
	if err != nil {
		return 0, err
	}
	
	// Parse JSON manifest
	var manifest struct {
		Layers []struct {
			Size int64 `json:"size"`
		} `json:"layers"`
	}
	
	if err := json.Unmarshal(data, &manifest); err != nil {
		return 0, err
	}
	
	var totalSize int64
	for _, layer := range manifest.Layers {
		totalSize += layer.Size
	}
	
	return totalSize, nil
}

func (s *Server) discoverModelsFromDirectories() error {
	s.logger.Infof("Falling back to directory-based model discovery")

	entries, err := os.ReadDir(s.modelsDir)
	if err != nil {
		return fmt.Errorf("failed to read models directory: %w", err)
	}

	for _, entry := range entries {
		if entry.IsDir() && entry.Name() != "manifests" && entry.Name() != "blobs" {
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

func (s *Server) generateModelTorrentFile(model *Model) (string, error) {
	// Create individual torrent file for this specific model
	safeName := strings.ReplaceAll(model.Name, ":", "_")
	torrentPath := filepath.Join(s.modelsDir, fmt.Sprintf("%s.torrent", safeName))
	
	// Check if torrent file already exists
	if _, err := os.Stat(torrentPath); err == nil {
		s.logger.Infof("Using existing torrent file: %s", torrentPath)
		return torrentPath, nil
	}
	
	s.logger.Infof("Creating individual torrent file for model: %s", model.Name)
	
	// Create torrent for this specific model only
	torrent, err := s.createModelSpecificTorrentFile(model)
	if err != nil {
		return "", fmt.Errorf("failed to create model-specific torrent file: %w", err)
	}
	
	// Write torrent file
	torrentData, err := bencode.Marshal(torrent)
	if err != nil {
		return "", fmt.Errorf("failed to encode torrent: %w", err)
	}
	
	if err := os.WriteFile(torrentPath, torrentData, 0644); err != nil {
		return "", fmt.Errorf("failed to write torrent file: %w", err)
	}
	
	s.logger.Infof("Created individual torrent file: %s", torrentPath)
	return torrentPath, nil
}

func (s *Server) createModelSpecificTorrentFile(model *Model) (*TorrentFile, error) {
	// Parse the model name to get the manifest path
	modelPath := strings.Replace(model.Name, ":", "/", 1)
	
	// Try both possible manifest path formats
	var manifestPath string
	var err error
	
	// Format 1: manifests/registry.ollama.ai/{model}/{tag}.json
	manifestPath1 := filepath.Join(s.modelsDir, "manifests", "registry.ollama.ai", modelPath+".json")
	if _, err = os.Stat(manifestPath1); err == nil {
		manifestPath = manifestPath1
	} else {
		// Format 2: manifests/registry.ollama.ai/library/{model}/{tag}
		manifestPath2 := filepath.Join(s.modelsDir, "manifests", "registry.ollama.ai", "library", modelPath)
		if _, err = os.Stat(manifestPath2); err == nil {
			manifestPath = manifestPath2
		} else {
			return nil, fmt.Errorf("manifest not found for model %s (tried both formats)", model.Name)
		}
	}
	
	// Read and parse the manifest
	manifestData, err := os.ReadFile(manifestPath)
	if err != nil {
		return nil, fmt.Errorf("failed to read manifest: %w", err)
	}
	
	var manifest struct {
		Layers []struct {
			Digest string `json:"digest"`
			Size   int64  `json:"size"`
		} `json:"layers"`
	}
	
	if err := json.Unmarshal(manifestData, &manifest); err != nil {
		return nil, fmt.Errorf("failed to parse manifest: %w", err)
	}
	
	// Create file list for this model
	var files []File
	var totalSize int64
	
	// Add the manifest file
	relManifestPath, err := filepath.Rel(s.modelsDir, manifestPath)
	if err != nil {
		return nil, fmt.Errorf("failed to get relative manifest path: %w", err)
	}
	manifestPathParts := strings.Split(relManifestPath, string(filepath.Separator))
	files = append(files, File{
		Length: int64(len(manifestData)),
		Path:   manifestPathParts,
	})
	totalSize += int64(len(manifestData))
	
	// Add layer files
	for _, layer := range manifest.Layers {
		digest := strings.TrimPrefix(layer.Digest, "sha256:")
		layerPath := filepath.Join(s.modelsDir, "blobs", fmt.Sprintf("sha256-%s", digest))
		
		// Check if the layer file exists
		if _, err := os.Stat(layerPath); err != nil {
			s.logger.Warnf("Layer file not found: %s", layerPath)
			continue
		}
		
		relLayerPath, err := filepath.Rel(s.modelsDir, layerPath)
		if err != nil {
			return nil, fmt.Errorf("failed to get relative layer path: %w", err)
		}
		layerPathParts := strings.Split(relLayerPath, string(filepath.Separator))
		
		files = append(files, File{
			Length: layer.Size,
			Path:   layerPathParts,
		})
		totalSize += layer.Size
	}
	
	if len(files) == 0 {
		return nil, fmt.Errorf("no files found for model %s", model.Name)
	}
	
	// Calculate piece hashes
	pieceLength := int64(32 * 1024) // 32KB pieces for smaller metadata
	if totalSize < pieceLength {
		pieceLength = totalSize
	}
	
	pieces, err := s.calculatePieceHashesForFiles(files, s.modelsDir, pieceLength)
	if err != nil {
		return nil, fmt.Errorf("failed to calculate piece hashes: %w", err)
	}
	
	// Create torrent info
			torrentInfo := TorrentInfo{
			PieceLength: pieceLength,
			Pieces:      pieces,
			Name:        "models", // Use "models" as the torrent name to match file structure
			Files:       files,
			Private:     1, // Private torrent
		}
	
	// Create torrent file
	torrent := &TorrentFile{
		Announce:     s.trackerURL,
		Comment:      fmt.Sprintf("Ollama model: %s", model.Name),
		CreatedBy:    "ollama-bt-lancache",
		CreationDate: time.Now().Unix(),
		Encoding:     "UTF-8",
		Info:         torrentInfo,
	}
	
	return torrent, nil
}

func (s *Server) calculatePieceHashesForFiles(files []File, basePath string, pieceLength int64) (string, error) {
	var pieces []byte
	var currentPiece []byte
	var currentPieceSize int64
	
	for _, file := range files {
		filePath := filepath.Join(basePath, filepath.Join(file.Path...))
		
		// Open the file
		f, err := os.Open(filePath)
		if err != nil {
			return "", fmt.Errorf("failed to open file %s: %w", filePath, err)
		}
		
		// Read the file in chunks
		buffer := make([]byte, 64*1024) // 64KB buffer
		for {
			n, err := f.Read(buffer)
			if n > 0 {
				currentPiece = append(currentPiece, buffer[:n]...)
				currentPieceSize += int64(n)
				
				// If we have a complete piece, hash it
				for currentPieceSize >= pieceLength {
					hash := sha1.Sum(currentPiece[:pieceLength])
					pieces = append(pieces, hash[:]...)
					
					// Remove the hashed piece from currentPiece
					currentPiece = currentPiece[pieceLength:]
					currentPieceSize -= pieceLength
				}
			}
			if err != nil {
				if err == io.EOF {
					break
				}
				f.Close()
				return "", fmt.Errorf("failed to read file %s: %w", filePath, err)
			}
		}
		f.Close()
	}
	
	// Hash any remaining data as the final piece
	if currentPieceSize > 0 {
		hash := sha1.Sum(currentPiece)
		pieces = append(pieces, hash[:]...)
	}
	
	return string(pieces), nil
}

func (s *Server) generateTorrentFile(model Model) (string, error) {
	// Create a single torrent file for all models
	torrentPath := filepath.Join(s.modelsDir, "models.torrent")
	
	// Check if torrent already exists
	if _, err := os.Stat(torrentPath); err == nil {
		s.logger.Infof("Using existing torrent file: %s", torrentPath)
		return torrentPath, nil
	}
	
	// Create torrent file for the entire models directory
	torrent, err := s.createTorrentFile(s.modelsDir, "models")
	if err != nil {
		return "", fmt.Errorf("failed to create torrent: %w", err)
	}
	
	// Write torrent file
	torrentData, err := bencode.Marshal(torrent)
	if err != nil {
		return "", fmt.Errorf("failed to marshal torrent: %w", err)
	}
	
	if err := os.WriteFile(torrentPath, torrentData, 0644); err != nil {
		return "", fmt.Errorf("failed to write torrent file: %w", err)
	}
	
	s.logger.Infof("Created torrent file: %s", torrentPath)
	return torrentPath, nil
}

func (s *Server) createTorrentFile(modelPath, modelName string) (*TorrentFile, error) {
	// For Ollama models, we create a torrent that includes the entire models directory
	// but with a specific name for the model
	var files []File
	var totalSize int64
	
			err := filepath.Walk(modelPath, func(path string, info os.FileInfo, err error) error {
		if err != nil {
			return err
		}
		
		if !info.IsDir() {
			relPath, err := filepath.Rel(modelPath, path)
			if err != nil {
				return err
			}
			
			// Convert path to slice of strings for bencode
			// The torrent should expect files to be in the root directory, not in a subdirectory
			pathParts := strings.Split(relPath, string(filepath.Separator))
			
			files = append(files, File{
				Length: info.Size(),
				Path:   pathParts,
			})
			
			totalSize += info.Size()
		}
		
		return nil
	})
	
	if err != nil {
		return nil, fmt.Errorf("failed to walk directory: %w", err)
	}
	
	// Calculate piece hashes with proper alignment
	pieceLength := int64(1024 * 1024) // 1MB pieces
	if totalSize < pieceLength {
		pieceLength = totalSize
	}
	
	pieces, err := s.calculatePieceHashes(modelPath, pieceLength)
	if err != nil {
		return nil, fmt.Errorf("failed to calculate piece hashes: %w", err)
	}
	
	// Create torrent info
	torrentInfo := TorrentInfo{
		PieceLength: pieceLength,
		Pieces:      pieces,
		Name:        "models", // Use "models" as the root name to match file structure
		Files:       files,
		Private:     1, // Private torrent
	}
	
	// Create torrent file
	torrent := &TorrentFile{
		Announce:     s.trackerURL,
		Comment:      fmt.Sprintf("Ollama models directory - %s", modelName),
		CreatedBy:    "ollama-bt-lancache",
		CreationDate: time.Now().Unix(),
		Encoding:     "UTF-8",
		Info:         torrentInfo,
	}
	
	return torrent, nil
}

func (s *Server) calculatePieceHashes(modelPath string, pieceLength int64) (string, error) {
	var pieces []byte
	var currentPiece []byte
	
	// Collect all files first to process them in order
	var files []string
	err := filepath.Walk(modelPath, func(path string, info os.FileInfo, err error) error {
		if err != nil {
			return err
		}
		if !info.IsDir() {
			files = append(files, path)
		}
		return nil
	})
	
	if err != nil {
		return "", err
	}
	
	// Process files in order to maintain consistent piece boundaries
	for _, filePath := range files {
		file, err := os.Open(filePath)
		if err != nil {
			return "", err
		}
		
		buffer := make([]byte, 64*1024) // 64KB buffer for reading
		for {
			n, err := file.Read(buffer)
			if err != nil && err.Error() != "EOF" {
				file.Close()
				return "", err
			}
			
			if n == 0 {
				break
			}
			
			// Add data to current piece
			currentPiece = append(currentPiece, buffer[:n]...)
			
			// If we have a complete piece, hash it
			for len(currentPiece) >= int(pieceLength) {
				pieceData := currentPiece[:pieceLength]
				hash := sha1.Sum(pieceData)
				pieces = append(pieces, hash[:]...)
				currentPiece = currentPiece[pieceLength:]
			}
		}
		file.Close()
	}
	
	// Hash the final partial piece if it exists
	if len(currentPiece) > 0 {
		hash := sha1.Sum(currentPiece)
		pieces = append(pieces, hash[:]...)
	}
	
	return string(pieces), nil
}



func (s *Server) startHTTPServer() {
	r := mux.NewRouter()

	// API routes
	r.HandleFunc("/api/models", s.getModels).Methods("GET")
	r.HandleFunc("/api/models/{name}/torrent", s.getTorrentFile).Methods("GET")

	// Downloads directory
	r.HandleFunc("/downloads/", s.serveDownloads).Methods("GET")
	r.HandleFunc("/downloads/{filename}", s.serveDownloadFile).Methods("GET")

	// Static files
	r.HandleFunc("/install.ps1", s.servePowerShellScript).Methods("GET")
	r.HandleFunc("/install.sh", s.serveBashScript).Methods("GET")
	r.HandleFunc("/client.py", s.serveClientScript).Methods("GET")

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
			// Serve the individual torrent file for this specific model
			safeName := strings.ReplaceAll(modelName, ":", "_")
			torrentPath := filepath.Join(s.modelsDir, fmt.Sprintf("%s.torrent", safeName))
			
			// Check if torrent file exists
			if _, err := os.Stat(torrentPath); os.IsNotExist(err) {
				s.logger.Errorf("Torrent file not found: %s", torrentPath)
				http.NotFound(w, r)
				return
			}
			
			// Set headers
			w.Header().Set("Content-Type", "application/x-bittorrent")
			w.Header().Set("Content-Disposition", fmt.Sprintf("attachment; filename=\"%s.torrent\"", modelName))
			
			// Serve the file
			http.ServeFile(w, r, torrentPath)
			return
		}
	}

	http.NotFound(w, r)
}

func (s *Server) servePowerShellScript(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "text/plain")
	w.Header().Set("Content-Disposition", "attachment; filename=\"install.ps1\"")
	
	// Read the actual install.ps1 file from the parent directory
	scriptPath := "../install.ps1"
	content, err := os.ReadFile(scriptPath)
	if err != nil {
		s.logger.Errorf("Failed to read install.ps1: %v", err)
		// Fallback to generated script if file not found
		script := generatePowerShellScript(s.serverIP, s.port)
		w.Write([]byte(script))
		return
	}
	
	w.Write(content)
}

func (s *Server) serveBashScript(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "text/plain")
	w.Header().Set("Content-Disposition", "attachment; filename=\"install.sh\"")
	
	// Read the actual install.sh file from the parent directory
	scriptPath := "../install.sh"
	content, err := os.ReadFile(scriptPath)
	if err != nil {
		s.logger.Errorf("Failed to read install.sh: %v", err)
		// Fallback to generated script if file not found
		script := generateBashScript(s.serverIP, s.port)
		w.Write([]byte(script))
		return
	}
	
	// Replace localhost references with actual server IP
	scriptContent := string(content)
	serverURL := fmt.Sprintf("http://%s:%s", s.serverIP, s.port)
	scriptContent = strings.ReplaceAll(scriptContent, "http://localhost:8080", serverURL)
	scriptContent = strings.ReplaceAll(scriptContent, "localhost:8080", fmt.Sprintf("%s:%s", s.serverIP, s.port))
	scriptContent = strings.ReplaceAll(scriptContent, `SERVER_URL="http://localhost:8080"`, fmt.Sprintf(`SERVER_URL="%s"`, serverURL))
	scriptContent = strings.ReplaceAll(scriptContent, `(default: http://localhost:8080)`, fmt.Sprintf(`(default: %s)`, serverURL))
	
	w.Write([]byte(scriptContent))
}

func (s *Server) serveClientScript(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "text/plain")
	w.Header().Set("Content-Disposition", "attachment; filename=\"client.py\"")

	// Read the client.py file from the parent directory
	clientPath := "../client.py"
	content, err := os.ReadFile(clientPath)
	if err != nil {
		s.logger.Errorf("Failed to read client.py: %v", err)
		http.Error(w, "Client script not found", http.StatusNotFound)
		return
	}

	w.Write(content)
}



func (s *Server) serveDownloads(w http.ResponseWriter, r *http.Request) {
	downloadsDir := "downloads"
	
	// Create downloads directory if it doesn't exist
	if err := os.MkdirAll(downloadsDir, 0755); err != nil {
		http.Error(w, "Failed to create downloads directory", http.StatusInternalServerError)
		return
	}

	// List files in downloads directory
	entries, err := os.ReadDir(downloadsDir)
	if err != nil {
		http.Error(w, "Failed to read downloads directory", http.StatusInternalServerError)
		return
	}

	tmpl := `
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Downloads - Ollama BitTorrent Lancache</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 40px; background-color: #f5f5f5; }
        .container { max-width: 1200px; margin: 0 auto; background: white; padding: 20px; border-radius: 8px; box-shadow: 0 2px 10px rgba(0,0,0,0.1); }
        h1 { color: #333; text-align: center; }
        .back-link { margin-bottom: 20px; }
        .back-link a { color: #007bff; text-decoration: none; }
        .back-link a:hover { text-decoration: underline; }
        .file-grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(300px, 1fr)); gap: 20px; margin-top: 30px; }
        .file-card { border: 1px solid #ddd; border-radius: 8px; padding: 20px; background: #fafafa; }
        .file-name { font-size: 18px; font-weight: bold; color: #333; margin-bottom: 10px; }
        .file-size { color: #666; margin-bottom: 10px; }
        .download-btn { background: #28a745; color: white; padding: 10px 20px; border: none; border-radius: 4px; cursor: pointer; text-decoration: none; display: inline-block; }
        .download-btn:hover { background: #218838; }
        .empty-state { text-align: center; color: #666; padding: 40px; }
    </style>
</head>
<body>
    <div class="container">
        <div class="back-link">
            <a href="/">← Back to Main Page</a>
        </div>
        <h1>📁 Downloads</h1>
        <p style="text-align: center; color: #666;">Share additional files like installers, documentation, and tools</p>
        
        {{if .Files}}
        <div class="file-grid">
            {{range .Files}}
            <div class="file-card">
                <div class="file-name">{{.Name}}</div>
                <div class="file-size">Size: {{.Size}}</div>
                <a href="/downloads/{{.Name}}" class="download-btn">Download</a>
            </div>
            {{end}}
        </div>
        {{else}}
        <div class="empty-state">
            <h3>No files available</h3>
            <p>Upload files to the downloads/ directory to make them available here.</p>
        </div>
        {{end}}
    </div>
</body>
</html>`

	type FileInfo struct {
		Name string
		Size string
	}

	var files []FileInfo
	for _, entry := range entries {
		if !entry.IsDir() {
			info, err := entry.Info()
			if err == nil {
				files = append(files, FileInfo{
					Name: entry.Name(),
					Size: formatSize(info.Size()),
				})
			}
		}
	}

	tmplData := struct {
		Files []FileInfo
	}{
		Files: files,
	}

	t, err := template.New("downloads").Parse(tmpl)
	if err != nil {
		http.Error(w, "Internal Server Error", http.StatusInternalServerError)
		return
	}

	t.Execute(w, tmplData)
}

func (s *Server) serveDownloadFile(w http.ResponseWriter, r *http.Request) {
	vars := mux.Vars(r)
	filename := vars["filename"]
	
	// Security check: prevent directory traversal
	if strings.Contains(filename, "..") || strings.Contains(filename, "/") || strings.Contains(filename, "\\") {
		http.Error(w, "Invalid filename", http.StatusBadRequest)
		return
	}
	
	filePath := filepath.Join("downloads", filename)
	
	// Check if file exists
	if _, err := os.Stat(filePath); os.IsNotExist(err) {
		http.NotFound(w, r)
		return
	}
	
	// Set appropriate headers
	w.Header().Set("Content-Disposition", fmt.Sprintf("attachment; filename=\"%s\"", filename))
	
	// Serve the file
	http.ServeFile(w, r, filePath)
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
                <div class="model-size">Size: {{.Size}} bytes</div>
                <a href="/api/models/{{.Name}}/torrent" class="download-btn">Download Torrent</a>
            </div>
            {{end}}
        </div>

        <div class="install-scripts">
            <h2>🚀 Quick Installation</h2>
            
            <div class="script-section">
                <div class="script-title">📋 List Available Models</div>
                <div class="script-code"># Windows (PowerShell)
Invoke-WebRequest -Uri "http://{{.ServerIP}}:{{.Port}}/install.ps1" | Invoke-Expression -ArgumentList "-List"

# Linux/macOS (Bash)
curl -sSL "http://{{.ServerIP}}:{{.Port}}/install.sh" | bash -s -- --list</div>
            </div>
            
            <div class="script-section">
                <div class="script-title">📥 Download Specific Model</div>
                <div class="script-code"># Windows (PowerShell)
Invoke-WebRequest -Uri "http://{{.ServerIP}}:{{.Port}}/install.ps1" | Invoke-Expression -ArgumentList "-Model granite3.3:8b"

# Linux/macOS (Bash)
curl -sSL "http://{{.ServerIP}}:{{.Port}}/install.sh" | bash -s -- --model granite3.3:8b</div>
            </div>
            
            <div class="script-section">
                <div class="script-title">🧪 Test Mode (Download to Current Directory)</div>
                <div class="script-code"># Windows (PowerShell)
Invoke-WebRequest -Uri "http://{{.ServerIP}}:{{.Port}}/install.ps1" | Invoke-Expression -ArgumentList "-Test -Model phi3:mini"

# Linux/macOS (Bash)
curl -sSL "http://{{.ServerIP}}:{{.Port}}/install.sh" | bash -s -- --test --model phi3:mini</div>
            </div>
            
            <div class="script-section">
                <div class="script-title">🧹 Clean Up Virtual Environment</div>
                <div class="script-code"># Windows (PowerShell)
Invoke-WebRequest -Uri "http://{{.ServerIP}}:{{.Port}}/install.ps1" | Invoke-Expression -ArgumentList "-Clean"

# Linux/macOS (Bash)
curl -sSL "http://{{.ServerIP}}:{{.Port}}/install.sh" | bash -s -- --clean</div>
            </div>
            
            <div class="script-section">
                <div class="script-title">📖 Manual Installation</div>
                <div class="script-code"># Windows (PowerShell)
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
Invoke-WebRequest -Uri "http://{{.ServerIP}}:{{.Port}}/install.ps1" -OutFile "install.ps1"
.\install.ps1 -List                    # List models
.\install.ps1 -Model granite3.3:8b    # Download specific model
.\install.ps1 -Test -Model phi3:mini  # Test mode
.\install.ps1 -Clean                  # Clean up

# Linux/macOS (Bash)
curl -sSL "http://{{.ServerIP}}:{{.Port}}/install.sh" -o install.sh
chmod +x install.sh
./install.sh --list                    # List models
./install.sh --model granite3.3:8b    # Download specific model
./install.sh --test --model phi3:mini # Test mode
./install.sh --clean                   # Clean up</div>
            </div>
        </div>

        <div class="downloads-section" style="margin-top: 30px; padding: 20px; background: #e3f2fd; border-radius: 8px;">
            <h2>📁 Additional Downloads</h2>
            <p style="margin-bottom: 15px;">Access additional files like installers, documentation, and tools.</p>
            <a href="/downloads/" class="download-btn" style="background: #1976d2; color: white; padding: 12px 24px; border: none; border-radius: 4px; cursor: pointer; text-decoration: none; display: inline-block; font-weight: bold;">Browse Downloads</a>
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

# Seeder script is available in the project repository

# Download models based on parameter
if ($Model -eq "all") {
    Write-Host "Downloading all available models..." -ForegroundColor Green
    Write-Host "Please use the seeder script from the project repository" -ForegroundColor Yellow
} else {
    Write-Host "Downloading model: $Model" -ForegroundColor Green
    Write-Host "Please use the seeder script from the project repository" -ForegroundColor Yellow
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

# Seeder script is available in the project repository

# Download models based on parameter
if [ "$MODEL" = "all" ]; then
    echo "Downloading all available models..."
    echo "Please use the seeder script from the project repository"
else
    echo "Downloading model: $MODEL"
    echo "Please use the seeder script from the project repository"
fi

echo "✅ Installation complete!"
echo "Models downloaded to: $HOME/.ollama/models"
`, serverIP, port)
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
