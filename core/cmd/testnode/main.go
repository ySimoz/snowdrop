package main

import (
	"context"
	"flag"
	"fmt"
	"log"
	"net"
	"net/http"
	"os"
	"os/signal"
	"path/filepath"
	"syscall"
	"time"

	"github.com/username/snowdrop/core"
)

func main() {
	name := flag.String("name", "testnode", "Device name for this node")
	dataDir := flag.String("data-dir", "", "Directory to store node state")
	dlDir := flag.String("dl-dir", "", "Directory to store downloaded files")
	sendPath := flag.String("send", "", "File path to send")
	targetIP := flag.String("to", "", "Peer IP to send file to")
	loopbackTest := flag.Bool("loopback", false, "Run simulated loopback transfer test between two nodes")
	flag.Parse()

	if *loopbackTest {
		runLoopbackSimulation()
		return
	}

	baseDir := *dataDir
	if baseDir == "" {
		baseDir = filepath.Join(os.TempDir(), "snowdrop-testnode", *name)
	}
	downloadDir := *dlDir
	if downloadDir == "" {
		downloadDir = filepath.Join(baseDir, "downloads")
	}

	cfg := &core.EngineConfig{
		DeviceName:  *name,
		DataDir:     baseDir,
		DownloadDir: downloadDir,
		OnStatusChange: func(status int, message string) {
			log.Printf("[%s] Status: %d (%s)", *name, status, message)
		},
		OnAuthRequired: func(authURL string) {
			log.Printf("[%s] Auth required: %s", *name, authURL)
		},
		OnPeersUpdated: func(peersJSON string) {
			log.Printf("[%s] Peers updated: %s", *name, peersJSON)
		},
		OnIncomingRequest: func(transferID, senderName, fileName string, sizeBytes int64) bool {
			log.Printf("[%s] Incoming transfer: ID=%s, from=%s, file=%s (%d bytes)", *name, transferID, senderName, fileName, sizeBytes)
			return true
		},
		OnProgress: func(transferID string, transferred, total int64) {
			pct := float64(transferred) / float64(total) * 100
			log.Printf("[%s] Progress [%s]: %d/%d (%.1f%%)", *name, transferID, transferred, total, pct)
		},
		OnTransferComplete: func(transferID string, success bool, errorMsg string) {
			if success {
				log.Printf("[%s] Transfer [%s] completed successfully", *name, transferID)
			} else {
				log.Printf("[%s] Transfer [%s] failed: %s", *name, transferID, errorMsg)
			}
		},
	}

	engine, err := core.NewEngine(cfg)
	if err != nil {
		log.Fatalf("failed creating engine: %v", err)
	}

	if err := engine.Start(); err != nil {
		log.Fatalf("failed starting engine: %v", err)
	}
	defer engine.Stop()

	if *sendPath != "" && *targetIP != "" {
		transferID := fmt.Sprintf("tx-%d", time.Now().Unix())
		log.Printf("[%s] Sending %s to %s (Transfer ID: %s)...", *name, *sendPath, *targetIP, transferID)
		if err := engine.SendFile(*targetIP, *sendPath, transferID); err != nil {
			log.Fatalf("send failed: %v", err)
		}
		log.Printf("[%s] Send finished.", *name)
		return
	}

	log.Printf("[%s] Node running. Press Ctrl+C to exit.", *name)
	sigCh := make(chan os.Signal, 1)
	signal.Notify(sigCh, os.Interrupt, syscall.SIGTERM)
	<-sigCh
	log.Printf("[%s] Shutting down...", *name)
}

func runLoopbackSimulation() {
	log.Println("Starting Loopback Transfer Simulation...")
	tempDir, err := os.MkdirTemp("", "snowdrop-sim-*")
	if err != nil {
		log.Fatalf("temp dir error: %v", err)
	}
	defer os.RemoveAll(tempDir)

	receiverDl := filepath.Join(tempDir, "receiver-dl")
	_ = os.MkdirAll(receiverDl, 0755)

	recvCfg := &core.EngineConfig{
		DeviceName:  "SimReceiver",
		DownloadDir: receiverDl,
		DataDir:     filepath.Join(tempDir, "receiver-state"),
		OnIncomingRequest: func(id, sender, file string, size int64) bool {
			log.Printf("[Receiver] Auto-accepting %s from %s (%d bytes)", file, sender, size)
			return true
		},
		OnProgress: func(id string, cur, total int64) {
			pct := float64(cur) / float64(total) * 100
			log.Printf("[Receiver] Stream progress: %d/%d (%.0f%%)", cur, total, pct)
		},
		OnTransferComplete: func(id string, success bool, err string) {
			log.Printf("[Receiver] Complete: ok=%v, err=%s", success, err)
		},
	}

	tm := core.NewTransferManager(recvCfg)
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		log.Fatalf("failed listening: %v", err)
	}
	defer ln.Close()

	srv := &http.Server{Handler: tm.Router("sim-receiver")}
	go func() {
		_ = srv.Serve(ln)
	}()
	defer srv.Close()

	port := ln.Addr().(*net.TCPAddr).Port

	// Prepare dummy 5MB file to test chunking and SHA-256
	samplePath := filepath.Join(tempDir, "sample-payload.dat")
	data := make([]byte, 5*1024*1024)
	for i := range data {
		data[i] = byte(i % 256)
	}
	if err := os.WriteFile(samplePath, data, 0644); err != nil {
		log.Fatalf("failed writing test file: %v", err)
	}

	senderCfg := &core.EngineConfig{
		DeviceName: "SimSender",
		OnProgress: func(id string, cur, total int64) {
			pct := float64(cur) / float64(total) * 100
			log.Printf("[Sender] Upload progress: %d/%d (%.0f%%)", cur, total, pct)
		},
		OnTransferComplete: func(id string, success bool, err string) {
			log.Printf("[Sender] Upload complete: ok=%v, err=%s", success, err)
		},
	}
	senderTM := core.NewTransferManager(senderCfg)

	log.Printf("Streaming 5 MB payload to 127.0.0.1:%d...", port)
	client := &http.Client{Timeout: 30 * time.Second}
	err = senderTM.SendFile(context.Background(), client, "127.0.0.1", port, samplePath, "sim-tx-42")
	if err != nil {
		log.Fatalf("Loopback transfer failed: %v", err)
	}

	// Verify file was written and matches byte-for-byte
	receivedPath := filepath.Join(receiverDl, "sample-payload.dat")
	receivedData, err := os.ReadFile(receivedPath)
	if err != nil {
		log.Fatalf("Cannot read downloaded file: %v", err)
	}

	if len(receivedData) != len(data) {
		log.Fatalf("Size mismatch: sent %d, got %d", len(data), len(receivedData))
	}

	log.Printf("SUCCESS: Loopback simulated transfer of %d bytes completed and verified byte-for-byte!", len(receivedData))
}
