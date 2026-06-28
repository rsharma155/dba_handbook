package main

import (
	"context"
	"encoding/json"
	"io"
	"log"
	"net/http"
	"os"
	"strings"
	"sync"
	"time"

	"github.com/google/uuid"
)

type server struct {
	uiPath      string
	httpServer  *http.Server
	connections sync.Map
}

func newServer(uiPath string) *server {
	return &server{uiPath: uiPath}
}

func (s *server) listen(addr string) error {
	mux := http.NewServeMux()
	mux.HandleFunc("/api/ping", s.handlePing)
	mux.HandleFunc("/api/connect", s.handleConnect)
	mux.HandleFunc("/api/disconnect", s.handleDisconnect)
	mux.HandleFunc("/api/execute", s.handleExecute)
	mux.HandleFunc("/", s.handleUI)

	s.httpServer = &http.Server{
		Addr:              addr,
		Handler:           cors(mux),
		ReadHeaderTimeout: 10 * time.Second,
	}
	return s.httpServer.ListenAndServe()
}

func (s *server) shutdown() error {
	if s.httpServer == nil {
		return nil
	}
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	s.connections.Range(func(key, value any) bool {
		if h, ok := value.(*connectionHolder); ok {
			_ = h.DB.Close()
		}
		s.connections.Delete(key)
		return true
	})
	return s.httpServer.Shutdown(ctx)
}

func cors(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Access-Control-Allow-Origin", "*")
		w.Header().Set("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
		w.Header().Set("Access-Control-Allow-Headers", "Content-Type")
		if r.Method == http.MethodOptions {
			w.WriteHeader(http.StatusOK)
			return
		}
		next.ServeHTTP(w, r)
	})
}

func writeJSON(w http.ResponseWriter, status int, payload any) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(payload)
}

func readJSON(r *http.Request, dest any) error {
	defer r.Body.Close()
	body, err := io.ReadAll(r.Body)
	if err != nil {
		return err
	}
	return json.Unmarshal(body, dest)
}

func (s *server) handlePing(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		writeJSON(w, http.StatusMethodNotAllowed, map[string]string{"error": "method not allowed"})
		return
	}
	ids := []string{}
	s.connections.Range(func(key, _ any) bool {
		if id, ok := key.(string); ok {
			ids = append(ids, id)
		}
		return true
	})
	writeJSON(w, http.StatusOK, map[string]any{
		"pong":        true,
		"time":        time.Now().UTC().Format(time.RFC3339),
		"connections": ids,
	})
}

type connectRequest struct {
	Engine           string `json:"engine"`
	Host             string `json:"host"`
	Port             int    `json:"port"`
	Database         string `json:"database"`
	Username         string `json:"username"`
	Password         string `json:"password"`
	SSLMode          string `json:"sslMode"`
	TrustCertificate *bool  `json:"trustCertificate"`
}

func (s *server) handleConnect(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		writeJSON(w, http.StatusMethodNotAllowed, map[string]string{"error": "method not allowed"})
		return
	}
	started := time.Now()
	var req connectRequest
	if err := readJSON(r, &req); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]any{"success": false, "error": err.Error()})
		return
	}

	trust := true
	if req.TrustCertificate != nil {
		trust = *req.TrustCertificate
	}

	cfg := connectConfig{
		Engine:           strings.ToLower(strings.TrimSpace(req.Engine)),
		Host:             req.Host,
		Port:             req.Port,
		Database:         req.Database,
		Username:         req.Username,
		Password:         req.Password,
		SSLMode:          req.SSLMode,
		TrustCertificate: trust,
	}

	db, err := openConnection(cfg)
	if err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]any{
			"success":    false,
			"error":      err.Error(),
			"durationMs": time.Since(started).Milliseconds(),
		})
		return
	}

	info, err := describeConnection(db, cfg.Engine, cfg.Database)
	if err != nil {
		_ = db.Close()
		writeJSON(w, http.StatusBadRequest, map[string]any{
			"success":    false,
			"error":      err.Error(),
			"durationMs": time.Since(started).Milliseconds(),
		})
		return
	}

	id := uuid.NewString()
	holder := &connectionHolder{
		ID:       id,
		Engine:   cfg.Engine,
		Database: cfg.Database,
		DB:       db,
		Config:   cfg,
	}
	s.connections.Store(id, holder)

	writeJSON(w, http.StatusOK, map[string]any{
		"success":      true,
		"connectionId": id,
		"server":       info,
		"durationMs":   time.Since(started).Milliseconds(),
	})
	log.Printf("connected [%s] %s", cfg.Engine, cfg.Host)
}

type disconnectRequest struct {
	ConnectionID string `json:"connectionId"`
}

func (s *server) handleDisconnect(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		writeJSON(w, http.StatusMethodNotAllowed, map[string]string{"error": "method not allowed"})
		return
	}
	var req disconnectRequest
	if err := readJSON(r, &req); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]any{"success": false, "error": err.Error()})
		return
	}
	if v, ok := s.connections.LoadAndDelete(req.ConnectionID); ok {
		if h, ok := v.(*connectionHolder); ok {
			_ = h.DB.Close()
		}
	}
	writeJSON(w, http.StatusOK, map[string]any{"success": true})
}

type executeRequest struct {
	ConnectionID string `json:"connectionId"`
	SQL          string `json:"sql"`
	Database     string `json:"database"`
}

func (s *server) handleExecute(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		writeJSON(w, http.StatusMethodNotAllowed, map[string]string{"error": "method not allowed"})
		return
	}
	started := time.Now()
	var req executeRequest
	if err := readJSON(r, &req); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]any{"success": false, "error": err.Error()})
		return
	}

	v, ok := s.connections.Load(req.ConnectionID)
	if !ok {
		writeJSON(w, http.StatusBadRequest, map[string]any{"success": false, "error": "not connected"})
		return
	}
	holder := v.(*connectionHolder)

	tables, messages, err := executeSQL(holder, req.SQL, req.Database)
	if err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]any{
			"success":    false,
			"error":      err.Error(),
			"durationMs": time.Since(started).Milliseconds(),
		})
		log.Printf("execute failed: %v", err)
		return
	}

	batchCount := len(splitSQLBatches(holder.Engine, req.SQL))
	writeJSON(w, http.StatusOK, map[string]any{
		"success":    true,
		"tables":     tables,
		"messages":   messages,
		"durationMs": time.Since(started).Milliseconds(),
		"tableCount": len(tables),
		"batchCount": batchCount,
	})
}

func (s *server) handleUI(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}
	if r.URL.Path != "/" {
		http.NotFound(w, r)
		return
	}
	data, err := os.ReadFile(s.uiPath)
	if err != nil {
		http.Error(w, "UI not found", http.StatusNotFound)
		return
	}
	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	_, _ = w.Write(data)
}
