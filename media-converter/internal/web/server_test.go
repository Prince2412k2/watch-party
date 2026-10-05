package web

import (
	"github.com/snuffkin/media-converter/internal/config"
	"github.com/snuffkin/media-converter/internal/scanner"
	"github.com/snuffkin/media-converter/internal/storage"
	"net/http/httptest"
	"path/filepath"
	"testing"
)

func TestControlPlaneRequiresServiceCredential(t *testing.T) {
	s, err := storage.Open(filepath.Join(t.TempDir(), "jobs.db"))
	if err != nil {
		t.Fatal(err)
	}
	defer s.Close()
	h := Handler(config.Config{APIKey: "private-key"}, s, scanner.Scanner{Store: s})
	for _, auth := range []string{"", "private-key", "Bearer wrong", "Bearer private-key"} {
		r := httptest.NewRequest("GET", "/api/state", nil)
		r.Header.Set("Authorization", auth)
		w := httptest.NewRecorder()
		h.ServeHTTP(w, r)
		want := 401
		if auth == "Bearer private-key" {
			want = 200
		}
		if w.Code != want {
			t.Fatalf("auth=%q status=%d body=%s", auth, w.Code, w.Body.String())
		}
	}
}
