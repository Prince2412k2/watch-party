package config

import (
	"fmt"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"time"
)

type Config struct {
	MoviesDir, TVDir, DataDir string
	Schedule, LogLevel        string
	Timezone                  *time.Location
	MaxConcurrent, Priority   int
	DeleteOriginal, DryRun    bool
	Strict, DeepValidation    bool
	MinFreeSpaceGB            float64
	ExcludePatterns           []string
	IncludeSamples            bool
	FFmpeg, FFprobe           string
	SonarrURL, SonarrAPIKey   string
	RadarrURL, RadarrAPIKey   string
	JellyfinURL, JellyfinKey  string
}

func Load() (Config, error) {
	tz := env("TZ", "UTC")
	loc, err := time.LoadLocation(tz)
	if err != nil {
		return Config{}, fmt.Errorf("load TZ %q: %w", tz, err)
	}
	c := Config{
		MoviesDir: env("MOVIES_DIR", "/media/movies"), TVDir: env("TV_DIR", "/media/tv"), DataDir: env("DATA_DIR", "/data"),
		Schedule: env("SCHEDULE", "0 3 * * *"), LogLevel: env("LOG_LEVEL", "info"), Timezone: loc,
		MaxConcurrent: envInt("MAX_CONCURRENT_JOBS", 1), Priority: envInt("DEFAULT_PRIORITY", 50),
		DeleteOriginal: envBool("DELETE_ORIGINAL", true), DryRun: envBool("DRY_RUN", false), Strict: envBool("STRICT_MODE", false),
		DeepValidation: envBool("DEEP_VALIDATION", false), MinFreeSpaceGB: envFloat("MIN_FREE_SPACE_GB", 20), IncludeSamples: envBool("INCLUDE_SAMPLES", false),
		FFmpeg: env("FFMPEG_PATH", "ffmpeg"), FFprobe: env("FFPROBE_PATH", "ffprobe"),
		SonarrURL: os.Getenv("SONARR_URL"), SonarrAPIKey: os.Getenv("SONARR_API_KEY"), RadarrURL: os.Getenv("RADARR_URL"), RadarrAPIKey: os.Getenv("RADARR_API_KEY"),
		JellyfinURL: os.Getenv("JELLYFIN_URL"), JellyfinKey: os.Getenv("JELLYFIN_API_KEY"),
	}
	for _, p := range strings.Split(env("EXCLUDE_PATTERNS", ""), ",") {
		if p = strings.TrimSpace(p); p != "" {
			c.ExcludePatterns = append(c.ExcludePatterns, p)
		}
	}
	if c.MaxConcurrent < 1 {
		return Config{}, fmt.Errorf("MAX_CONCURRENT_JOBS must be at least 1")
	}
	if c.Priority < 0 {
		return Config{}, fmt.Errorf("DEFAULT_PRIORITY must be non-negative")
	}
	if err := os.MkdirAll(c.DataDir, 0o750); err != nil {
		return Config{}, fmt.Errorf("create data directory: %w", err)
	}
	c.DataDir, _ = filepath.Abs(c.DataDir)
	return c, nil
}

func env(k, d string) string {
	if v := os.Getenv(k); v != "" {
		return v
	}
	return d
}
func envInt(k string, d int) int {
	v, e := strconv.Atoi(env(k, strconv.Itoa(d)))
	if e != nil {
		return d
	}
	return v
}
func envFloat(k string, d float64) float64 {
	v, e := strconv.ParseFloat(env(k, fmt.Sprint(d)), 64)
	if e != nil {
		return d
	}
	return v
}
func envBool(k string, d bool) bool {
	v, e := strconv.ParseBool(env(k, strconv.FormatBool(d)))
	if e != nil {
		return d
	}
	return v
}
