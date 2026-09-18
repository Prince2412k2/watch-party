package hooks

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"strings"
	"sync"
	"time"
)

type Config struct{ SonarrURL, SonarrKey, RadarrURL, RadarrKey, JellyfinURL, JellyfinKey string }
type Notifier struct {
	cfg           Config
	client        *http.Client
	mu            sync.Mutex
	jellyfinTimer *time.Timer
}

func New(c Config) *Notifier {
	return &Notifier{cfg: c, client: &http.Client{Timeout: 15 * time.Second}}
}
func (n *Notifier) RefreshPath(ctx context.Context, path string) []error {
	var errs []error
	if n.cfg.SonarrURL != "" && n.cfg.SonarrKey != "" && strings.Contains(strings.ToLower(path), "/tv/") {
		if e := n.post(ctx, n.cfg.SonarrURL+"/api/v3/command", n.cfg.SonarrKey, map[string]any{"name": "RescanSeries"}); e != nil {
			errs = append(errs, e)
		}
	}
	if n.cfg.RadarrURL != "" && n.cfg.RadarrKey != "" && strings.Contains(strings.ToLower(path), "/movies/") {
		if e := n.post(ctx, n.cfg.RadarrURL+"/api/v3/command", n.cfg.RadarrKey, map[string]any{"name": "RescanMovie"}); e != nil {
			errs = append(errs, e)
		}
	}
	return errs
}
func (n *Notifier) JellyfinRefresh(ctx context.Context) error {
	if n.cfg.JellyfinURL == "" || n.cfg.JellyfinKey == "" {
		return nil
	}
	return n.post(ctx, n.cfg.JellyfinURL+"/Library/Refresh", n.cfg.JellyfinKey, nil)
}
func (n *Notifier) QueueJellyfinRefresh() {
	if n.cfg.JellyfinURL == "" || n.cfg.JellyfinKey == "" {
		return
	}
	n.mu.Lock()
	defer n.mu.Unlock()
	if n.jellyfinTimer != nil {
		n.jellyfinTimer.Reset(2 * time.Minute)
		return
	}
	n.jellyfinTimer = time.AfterFunc(2*time.Minute, func() {
		ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
		defer cancel()
		_ = n.JellyfinRefresh(ctx)
		n.mu.Lock()
		n.jellyfinTimer = nil
		n.mu.Unlock()
	})
}
func (n *Notifier) post(ctx context.Context, url, key string, body any) error {
	var b bytes.Buffer
	if body != nil {
		_ = json.NewEncoder(&b).Encode(body)
	}
	req, e := http.NewRequestWithContext(ctx, http.MethodPost, strings.TrimRight(url, "/"), &b)
	if e != nil {
		return e
	}
	req.Header.Set("X-Api-Key", key)
	req.Header.Set("Authorization", "MediaBrowser Token=\""+key+"\"")
	req.Header.Set("Content-Type", "application/json")
	r, e := n.client.Do(req)
	if e != nil {
		return e
	}
	defer r.Body.Close()
	if r.StatusCode < 200 || r.StatusCode >= 300 {
		return fmt.Errorf("hook %s returned %s", url, r.Status)
	}
	return nil
}
