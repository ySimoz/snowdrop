package core

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net"
	"net/http"
	"os"
	"regexp"
	"strings"
	"sync"
	"time"

	"tailscale.com/client/local"
	"tailscale.com/tsnet"
)

// Engine represents an active Snowdrop node powered by tsnet
type Engine struct {
	config    *EngineConfig
	tsServer  *tsnet.Server
	listener  net.Listener
	httpSrv   *http.Server
	transfers *TransferManager
	ctx       context.Context
	cancel    context.CancelFunc
	wg        sync.WaitGroup
	mu        sync.Mutex
	status    int
	lastPeers string
}

// NewEngine initializes a Snowdrop engine instance
func NewEngine(cfg *EngineConfig) (*Engine, error) {
	if cfg == nil {
		return nil, errors.New("nil engine config")
	}
	if cfg.DataDir == "" {
		return nil, errors.New("empty data dir")
	}
	if cfg.DownloadDir == "" {
		return nil, errors.New("empty download dir")
	}
	if cfg.Port <= 0 {
		cfg.Port = DefaultPort
	}
	if cfg.DeviceName == "" {
		cfg.DeviceName = "device"
	}

	tm := NewTransferManager(cfg)
	ctx, cancel := context.WithCancel(context.Background())

	return &Engine{
		config:    cfg,
		transfers: tm,
		ctx:       ctx,
		cancel:    cancel,
		status:    StatusDisconnected,
	}, nil
}

// Start begins tsnet operation and HTTP service listener asynchronously
func (e *Engine) Start() error {
	e.mu.Lock()
	defer e.mu.Unlock()

	if err := os.MkdirAll(e.config.DataDir, 0700); err != nil {
		return fmt.Errorf("failed to create data dir: %w", err)
	}
	if err := os.MkdirAll(e.config.DownloadDir, 0755); err != nil {
		return fmt.Errorf("failed to create download dir: %w", err)
	}

	sanitizedName := sanitizeHostname(e.config.DeviceName)
	serverHostname := fmt.Sprintf("snowdrop-%s", sanitizedName)

	e.tsServer = &tsnet.Server{
		Dir:       e.config.DataDir,
		Hostname:  serverHostname,
		Ephemeral: false,
		UserLogf: func(format string, args ...any) {
			msg := fmt.Sprintf(format, args...)
			authURL := extractURL(msg)
			if authURL != "" && e.config.OnAuthRequired != nil {
				e.config.OnAuthRequired(authURL)
			}
		},
	}

	e.wg.Add(2)
	go e.runServer(serverHostname)
	go e.monitorStatus()

	e.updateStatus(StatusConnecting, "starting")
	return nil
}

func (e *Engine) runServer(serverHostname string) {
	defer e.wg.Done()

	if err := e.tsServer.Start(); err != nil {
		e.updateStatus(StatusError, err.Error())
		return
	}

	ln, err := e.tsServer.Listen("tcp", fmt.Sprintf(":%d", e.config.Port))
	if err != nil {
		_ = e.tsServer.Close()
		e.updateStatus(StatusError, err.Error())
		return
	}

	e.mu.Lock()
	e.listener = ln
	e.httpSrv = &http.Server{
		Handler:      e.transfers.Router(serverHostname),
		ReadTimeout:  10 * time.Minute,
		WriteTimeout: 10 * time.Minute,
	}
	srv := e.httpSrv
	e.mu.Unlock()

	if err := srv.Serve(ln); err != nil && !errors.Is(err, http.ErrServerClosed) && !errors.Is(err, net.ErrClosed) {
		e.updateStatus(StatusError, fmt.Sprintf("http server error: %v", err))
	}
}

func (e *Engine) monitorStatus() {
	defer e.wg.Done()

	ticker := time.NewTicker(2 * time.Second)
	defer ticker.Stop()

	var lc *local.Client
	for {
		select {
		case <-e.ctx.Done():
			return
		case <-ticker.C:
			if lc == nil {
				var err error
				lc, err = e.tsServer.LocalClient()
				if err != nil {
					continue
				}
			}

			st, err := lc.Status(e.ctx)
			if err != nil {
				continue
			}

			if st.AuthURL != "" && e.config.OnAuthRequired != nil {
				e.config.OnAuthRequired(st.AuthURL)
			}

			switch st.BackendState {
			case "NeedsLogin", "NeedsMachineAuth":
				e.updateStatus(StatusNeedsAuth, st.BackendState)
			case "Running":
				e.updateStatus(StatusConnected, "connected")
			case "Starting":
				e.updateStatus(StatusConnecting, "starting")
			case "Stopped", "NoState":
				e.updateStatus(StatusDisconnected, st.BackendState)
			}

			e.syncPeers(st)
		}
	}
}

func (e *Engine) syncPeers(st any) {
	lc, err := e.tsServer.LocalClient()
	if err != nil {
		return
	}
	ipnSt, err := lc.Status(e.ctx)
	if err != nil || ipnSt == nil {
		return
	}

	var peerList []PeerInfo
	for _, pk := range ipnSt.Peers() {
		peer := ipnSt.Peer[pk]
		if peer == nil {
			continue
		}

		var ips []string
		for _, addr := range peer.TailscaleIPs {
			ips = append(ips, addr.String())
		}

		peerList = append(peerList, PeerInfo{
			ID:          string(peer.ID),
			HostName:    peer.HostName,
			DNSName:     strings.TrimSuffix(peer.DNSName, "."),
			OS:          peer.OS,
			IPAddresses: ips,
			Online:      peer.Online,
		})
	}

	bytes, err := json.Marshal(peerList)
	if err != nil {
		return
	}
	jsonStr := string(bytes)
	if jsonStr != e.lastPeers {
		e.lastPeers = jsonStr
		if e.config.OnPeersUpdated != nil {
			e.config.OnPeersUpdated(jsonStr)
		}
	}
}

func (e *Engine) updateStatus(st int, msg string) {
	e.mu.Lock()
	e.status = st
	e.mu.Unlock()

	if e.config.OnStatusChange != nil {
		e.config.OnStatusChange(st, msg)
	}
}

// Stop terminates the engine and listeners
func (e *Engine) Stop() {
	e.mu.Lock()
	if e.cancel != nil {
		e.cancel()
	}
	if e.httpSrv != nil {
		_ = e.httpSrv.Close()
	}
	if e.listener != nil {
		_ = e.listener.Close()
	}
	if e.tsServer != nil {
		_ = e.tsServer.Close()
	}
	e.mu.Unlock()

	e.wg.Wait()
	e.updateStatus(StatusDisconnected, "stopped")
}

// SendFile initiates an outbound file transfer to a peer IP
func (e *Engine) SendFile(peerIP string, filePath string, transferID string) error {
	if e.tsServer == nil {
		return errors.New("engine not started")
	}
	client := e.tsServer.HTTPClient()
	return e.transfers.SendFile(e.ctx, client, peerIP, e.config.Port, filePath, transferID)
}

// CancelTransfer aborts an active transfer
func (e *Engine) CancelTransfer(transferID string) bool {
	return e.transfers.Cancel(transferID)
}

func sanitizeHostname(name string) string {
	reg := regexp.MustCompile("[^a-zA-Z0-9]+")
	sanitized := reg.ReplaceAllString(name, "-")
	sanitized = strings.Trim(sanitized, "-")
	sanitized = strings.ToLower(sanitized)
	if sanitized == "" {
		return "device"
	}
	if len(sanitized) > 32 {
		return sanitized[:32]
	}
	return sanitized
}

func extractURL(text string) string {
	r := regexp.MustCompile(`https?://[^\s]+`)
	return r.FindString(text)
}
