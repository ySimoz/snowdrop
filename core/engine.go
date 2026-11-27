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
	"runtime"
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
	tsStartDone chan struct{}
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
	if runtime.GOOS != "darwin" {
		_ = os.Setenv("TMPDIR", e.config.DataDir)
		if os.Getenv("HOME") == "" {
			_ = os.Setenv("HOME", e.config.DataDir)
		}
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
	e.tsStartDone = make(chan struct{})
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

	startErr := e.tsServer.Start()
	e.mu.Lock()
	doneCh := e.tsStartDone
	e.mu.Unlock()
	if doneCh != nil {
		close(doneCh)
	}
	if startErr != nil {
		e.updateStatus(StatusError, startErr.Error())
		return
	}
	if e.ctx.Err() != nil {
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
	peerList = deduplicatePeers(peerList)
	if peerList == nil {
		peerList = make([]PeerInfo, 0)
	}

	bytes, err := json.Marshal(peerList)
	if err != nil {
		return
	}
	jsonStr := string(bytes)
	e.mu.Lock()
	changed := jsonStr != e.lastPeers
	if changed {
		e.lastPeers = jsonStr
	}
	e.mu.Unlock()
	if changed && e.config.OnPeersUpdated != nil {
		e.config.OnPeersUpdated(jsonStr)
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
	tsSrv := e.tsServer
	startDone := e.tsStartDone
	e.mu.Unlock()

	go func() {
		if startDone != nil {
			<-startDone
		}
		if tsSrv != nil {
			_ = tsSrv.Close()
		}
		e.wg.Wait()
		e.updateStatus(StatusDisconnected, "stopped")
	}()
}

// StopAndWait terminates the engine and waits up to timeout for workers to exit
func (e *Engine) StopAndWait(timeout time.Duration) {
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
	tsSrv := e.tsServer
	startDone := e.tsStartDone
	e.mu.Unlock()

	done := make(chan struct{})
	go func() {
		// tsnet.Server.Close must not run before or concurrently with Start.
		if startDone != nil {
			<-startDone
		}
		if tsSrv != nil {
			_ = tsSrv.Close()
		}
		e.wg.Wait()
		close(done)
	}()

	if timeout > 0 {
		select {
		case <-done:
		case <-time.After(timeout):
		}
	} else {
		<-done
	}
	e.updateStatus(StatusDisconnected, "stopped")
}

// NotifyTransferComplete emits a completion callback via the transfer manager
func (e *Engine) NotifyTransferComplete(transferID string, success bool, errorMsg string) {
	if e.transfers != nil {
		e.transfers.notifyComplete(transferID, success, errorMsg)
	}
}

// SendFile initiates an outbound file transfer to a peer IP
func (e *Engine) SendFile(peerIP string, filePath string, transferID string) error {
	e.mu.Lock()
	tsSrv := e.tsServer
	e.mu.Unlock()
	if tsSrv == nil {
		e.NotifyTransferComplete(transferID, false, "engine not started")
		return errors.New("engine not started")
	}
	client := tsSrv.HTTPClient()
	sanitizedName := sanitizeHostname(e.config.DeviceName)
	serverHostname := fmt.Sprintf("snowdrop-%s", sanitizedName)
	return e.transfers.SendFile(e.ctx, client, peerIP, e.config.Port, filePath, transferID, serverHostname)
}

// SendBatch initiates an outbound multi-file batch transfer to a peer IP
func (e *Engine) SendBatch(peerIP string, batchID string, files []BatchSendSource) error {
	e.mu.Lock()
	tsSrv := e.tsServer
	e.mu.Unlock()
	if tsSrv == nil {
		e.NotifyTransferComplete(batchID, false, "engine not started")
		return errors.New("engine not started")
	}
	client := tsSrv.HTTPClient()
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
	if e.transfers != nil {
		e.transfers.SetApprovalConfig(requireApproval, autoAcceptTrusted)
	}
}

// SetDownloadDir updates the destination download directory safely
func (e *Engine) SetDownloadDir(dir string) error {
	if strings.TrimSpace(dir) == "" {
		return errors.New("empty download dir")
	}
	if err := os.MkdirAll(dir, 0755); err != nil {
		return fmt.Errorf("failed to create download dir: %w", err)
	}
	if e.transfers != nil {
		e.transfers.SetDownloadDir(dir)
	}
	return nil
}

// SignOut logs out the current node from Tailscale and requests a fresh login URL
func (e *Engine) SignOut() error {
	e.mu.Lock()
	tsSrv := e.tsServer
	e.mu.Unlock()

	if tsSrv == nil {
		return fmt.Errorf("engine not started")
	}

	lc, err := tsSrv.LocalClient()
	if err != nil {
		return fmt.Errorf("failed to get local client: %w", err)
	}

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	if err := lc.Logout(ctx); err != nil {
		return fmt.Errorf("failed to logout: %w", err)
	}

	// Request new interactive login so user can re-authenticate
	_ = lc.StartLoginInteractive(ctx)

	e.updateStatus(StatusNeedsAuth, "LoggedOut")
	return nil
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

// baseDeviceKey normalizes hostnames by stripping trailing Tailscale duplicate indices like "-1", "-2"
func baseDeviceKey(name string) string {
	lower := strings.ToLower(strings.TrimSpace(name))
	for i := len(lower) - 1; i >= 0; i-- {
		if lower[i] >= '0' && lower[i] <= '9' {
			continue
		}
		if lower[i] == '-' && i < len(lower)-1 {
			return lower[:i]
		}
		break
	}
	return lower
}

// deduplicatePeers suppresses stale offline duplicates when an active online node with the same base name exists
func deduplicatePeers(peers []PeerInfo) []PeerInfo {
	if len(peers) <= 1 {
		return peers
	}
	onlineBases := make(map[string]bool)
	for _, p := range peers {
		if p.Online {
			onlineBases[baseDeviceKey(p.HostName)] = true
		}
	}

	result := make([]PeerInfo, 0, len(peers))
	for _, p := range peers {
		base := baseDeviceKey(p.HostName)
		// If this peer is offline and there's an online peer with the same base name, suppress it
		if !p.Online && onlineBases[base] {
			continue
		}
		result = append(result, p)
	}
	return result
}
