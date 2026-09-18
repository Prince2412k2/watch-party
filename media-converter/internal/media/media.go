package media

import (
	"fmt"
	"path/filepath"
	"strings"
)

func Paths(source string) (target, temp string, err error) {
	if !strings.EqualFold(filepath.Ext(source), ".mkv") {
		return "", "", fmt.Errorf("not an MKV: %s", source)
	}
	base := strings.TrimSuffix(filepath.Base(source), filepath.Ext(source))
	dir := filepath.Dir(source)
	return filepath.Join(dir, base+".mp4"), filepath.Join(dir, "."+base+".media-converter.tmp.mp4"), nil
}

func Title(path string) string { return strings.TrimSuffix(filepath.Base(path), filepath.Ext(path)) }
