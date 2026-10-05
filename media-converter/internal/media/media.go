package media

import (
	"fmt"
	"path/filepath"
	"strings"
)

func Paths(source string) (target, temp string, err error) {
	if !Eligible(source) {
		return "", "", fmt.Errorf("not an eligible video: %s", source)
	}
	base := strings.TrimSuffix(filepath.Base(source), filepath.Ext(source))
	dir := filepath.Dir(source)
	return filepath.Join(dir, base+".mp4"), filepath.Join(dir, "."+base+".media-converter.tmp.mp4"), nil
}

// MP4 inputs are inspected too: incompatible old renditions are normalized in
// place only after validation. Hidden temporary files are never eligible.
func Eligible(path string) bool {
	switch strings.ToLower(filepath.Ext(path)) {
	case ".mp4", ".mkv", ".avi", ".webm", ".mov", ".m4v", ".ts", ".m2ts", ".mpg", ".mpeg", ".wmv", ".flv":
		return !strings.HasPrefix(filepath.Base(path), ".")
	}
	return false
}

func Title(path string) string { return strings.TrimSuffix(filepath.Base(path), filepath.Ext(path)) }
