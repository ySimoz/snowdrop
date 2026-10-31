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
	config      *EngineConfig
	tsServer    *tsnet.Server
	listener    net.Listener
	httpSrv     *http.Server
	transfers   *TransferManager
	trustStore  *TrustStore
	ctx         context.Context
	cancel      context.CancelFunc
	wg          sync.WaitGroup
	mu          sync.Mutex
	status      int
	authURL     string
	lastPeers   string
	peerNamesMu sync.RWMutex
	peerNames   map[string]string
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

	ts, _ := NewTrustStore(cfg.DataDir)
	tm := NewTransferManager(cfg, ts)
	ctx, cancel := context.WithCancel(context.Background())

	return &Engine{
		config:     cfg,
		transfers:  tm,
		trustStore: ts,
		ctx:        ctx,
		cancel:     cancel,
		status:     StatusDisconnected,
		peerNames:  make(map[string]string),
	}, nil
}

// Start begins tsnet operation and HTTP service listener asynchronously
func (e *Engine) Start() error {
	if err := os.MkdirAll(e.config.DataDir, 0700); err != nil {
		return fmt.Errorf("failed to create data dir: %w", err)
	}
	if err := os.MkdirAll(e.config.DownloadDir, 0755); err != nil {
		return fmt.Errorf("failed to create download dir: %w", err)
	}

	_ = os.Setenv("TS_LOGS_DIR", e.config.DataDir)
	_ = os.Setenv("TMPDIR", e.config.DataDir)
	if os.Getenv("HOME") == "" {
		_ = os.Setenv("HOME", e.config.DataDir)
	}

	sanitizedName := sanitizeHostname(e.config.DeviceName)
	serverHostname := fmt.Sprintf("snowdrop-%s", sanitizedName)

	e.mu.Lock()
	e.tsServer = &tsnet.Server{
		Dir:       e.config.DataDir,
		Hostname:  serverHostname,
		Ephemeral: false,
		UserLogf: func(format string, args ...any) {
			msg := fmt.Sprintf(format, args...)
			authURL := extractURL(msg)
			if authURL != "" {
				e.mu.Lock()
				e.authURL = authURL
				e.mu.Unlock()
				if e.config.OnAuthRequired != nil {
					e.config.OnAuthRequired(authURL)
				}
				e.updateStatus(StatusNeedsAuth, "NeedsLogin")
			}
		},
	}
	e.status = StatusConnecting
	e.mu.Unlock()

	e.wg.Add(2)
	go e.runServer(serverHostname)
	go e.monitorStatus()

	if e.config.OnStatusChange != nil {
		e.config.OnStatusChange(StatusConnecting, "starting")
	}
	return nil
}

func (e *Engine) runServer(serverHostname string) {
	defer e.wg.Done()

	if err := e.tsServer.Start(); err != nil {
		e.updateStatus(StatusError, err.Error())
		return
	}

	e.transfers.SetWhoIsResolver(func(ctx context.Context, remoteAddr string) (string, error) {
		lc, err := e.tsServer.LocalClient()
		if err != nil {
			return "", err
		}
		who, err := lc.WhoIs(ctx, remoteAddr)
		if err != nil || who == nil || who.Node == nil {
			return "", err
		}
		nodeName := who.Node.ComputedName
		if nodeName == "" {
			nodeName = who.Node.Hostinfo.Hostname()
		}
		return strings.ToLower(nodeName), nil
	})

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

			if st.AuthURL != "" {
				e.mu.Lock()
				e.authURL = st.AuthURL
				e.mu.Unlock()
				if e.config.OnAuthRequired != nil {
					e.config.OnAuthRequired(st.AuthURL)
				}
			}

			switch st.BackendState {
			case "Running":
				e.mu.Lock()
				e.authURL = ""
				e.mu.Unlock()
				e.updateStatus(StatusConnected, "connected")
			case "NeedsLogin", "NeedsMachineAuth":
				e.updateStatus(StatusNeedsAuth, st.BackendState)
			case "Starting":
				e.mu.Lock()
				hasAuth := e.authURL != ""
				e.mu.Unlock()
				if hasAuth {
					e.updateStatus(StatusNeedsAuth, "NeedsLogin")
				} else {
					e.updateStatus(StatusConnecting, "starting")
				}
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

	var snowdropPeers []PeerInfo
	var otherPeers []PeerInfo
	for _, pk := range ipnSt.Peers() {
		peer := ipnSt.Peer[pk]
		if peer == nil {
			continue
		}

		var ips []string
		for _, addr := range peer.TailscaleIPs {
			ips = append(ips, addr.String())
		}

		cleanHostName := peer.HostName
		isSnowdrop := strings.HasPrefix(strings.ToLower(peer.HostName), "snowdrop-")
		if isSnowdrop {
			cleanHostName = strings.TrimPrefix(peer.HostName, "snowdrop-")
		}

		primaryIP := ""
		if len(ips) > 0 {
			primaryIP = ips[0]
		}

		displayName := cleanHostName
		if isSnowdrop {
			e.peerNamesMu.RLock()
			cachedName, hasCached := e.peerNames[primaryIP]
			e.peerNamesMu.RUnlock()

			if hasCached && cachedName != "" {
				displayName = cachedName
			} else {
				displayName = humanizeHostname(cleanHostName)
				if peer.Online && primaryIP != "" {
					go e.fetchPeerInfo(primaryIP)
				}
			}
		} else {
			displayName = humanizeHostname(cleanHostName)
		}

		info := PeerInfo{
			ID:          string(peer.ID),
			HostName:    cleanHostName,
			DisplayName: displayName,
			DNSName:     strings.TrimSuffix(peer.DNSName, "."),
			OS:          peer.OS,
			IPAddresses: ips,
			Online:      peer.Online,
		}

		if isSnowdrop {
			snowdropPeers = append(snowdropPeers, info)
		} else {
			otherPeers = append(otherPeers, info)
		}
	}

	peerList := snowdropPeers
	if len(peerList) == 0 {
		peerList = otherPeers
	}
	if peerList == nil {
		peerList = make([]PeerInfo, 0)
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

// Stop terminates the engine and listeners asynchronously without blocking
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

	go func() {
		e.wg.Wait()
		e.updateStatus(StatusDisconnected, "stopped")
	}()
}

// SendFile initiates an outbound file transfer to a peer IP
func (e *Engine) SendFile(peerIP string, filePath string, transferID string) error {
	if e.tsServer == nil {
		return errors.New("engine not started")
	}
	client := e.tsServer.HTTPClient()
	sanitizedName := sanitizeHostname(e.config.DeviceName)
	serverHostname := fmt.Sprintf("snowdrop-%s", sanitizedName)
	return e.transfers.SendFile(e.ctx, client, peerIP, e.config.Port, filePath, transferID, serverHostname)
}

// SendBatch initiates an outbound multi-file batch transfer to a peer IP
func (e *Engine) SendBatch(peerIP string, batchID string, files []BatchSendSource) error {
	if e.tsServer == nil {
		return errors.New("engine not started")
	}
	client := e.tsServer.HTTPClient()
	sanitizedName := sanitizeHostname(e.config.DeviceName)
	serverHostname := fmt.Sprintf("snowdrop-%s", sanitizedName)
	return e.transfers.SendBatch(e.ctx, client, peerIP, e.config.Port, batchID, files, serverHostname)
}

// CancelTransfer aborts an active transfer
func (e *Engine) CancelTransfer(transferID string) bool {
	return e.transfers.Cancel(transferID)
}

// ResolveApproval resolves an incoming transfer approval request
func (e *Engine) ResolveApproval(transferID string, decision int) bool {
	if e.transfers == nil {
		return false
	}
	return e.transfers.ResolveApproval(transferID, decision)
}

// GetTrustedPeersJSON returns a JSON string of all remembered trusted peers
func (e *Engine) GetTrustedPeersJSON() string {
	if e.trustStore == nil {
		return "[]"
	}
	data, err := json.Marshal(e.trustStore.List())
	if err != nil {
		return "[]"
	}
	return string(data)
}

// RevokeTrusted removes a peer from trusted status
func (e *Engine) RevokeTrusted(nodeID string) bool {
	if e.trustStore == nil {
		return false
	}
	return e.trustStore.RevokeTrusted(nodeID) == nil
}

// SetApprovalConfig updates security approval preferences
func (e *Engine) SetApprovalConfig(requireApproval, autoAcceptTrusted bool) {
	e.mu.Lock()
	e.config.RequireApproval = requireApproval
	e.config.AutoAcceptTrusted = autoAcceptTrusted
	e.mu.Unlock()
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

func humanizeHostname(name string) string {
	parts := strings.Split(name, "-")
	var formatted []string
	for _, p := range parts {
		if p == "" {
			continue
		}
		formatted = append(formatted, strings.ToUpper(p[:1])+strings.ToLower(p[1:]))
	}
	if len(formatted) == 0 {
		return name
	}
	return strings.Join(formatted, " ")
}

func (e *Engine) fetchPeerInfo(ip string) {
	e.mu.Lock()
	tsSrv := e.tsServer
	e.mu.Unlock()
	if tsSrv == nil {
		return
	}

	ctx, cancel := context.WithTimeout(e.ctx, 2*time.Second)
	defer cancel()

	client := tsSrv.HTTPClient()
	url := fmt.Sprintf("http://%s:%d/v1/info", ip, e.config.Port)
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)
	if err != nil {
		return
	}
	resp, err := client.Do(req)
	if err != nil {
		return
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return
	}

	var info NodeInfo
	if err := json.NewDecoder(resp.Body).Decode(&info); err != nil {
		return
	}

	if info.DeviceName != "" {
		e.peerNamesMu.Lock()
		prev := e.peerNames[ip]
		e.peerNames[ip] = info.DeviceName
		e.peerNamesMu.Unlock()

		if prev != info.DeviceName {
			go e.syncPeers(nil)
		}
	}
}
