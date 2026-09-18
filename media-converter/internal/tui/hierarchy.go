package tui

import (
	"path/filepath"
	"regexp"
	"sort"
	"strconv"
	"strings"
	"unicode"

	"github.com/snuffkin/media-converter/internal/jobs"
)

type mediaKind int

const (
	kindOther mediaKind = iota
	kindMovie
	kindTV
)

type mediaRecord struct {
	job           jobs.Job
	kind          mediaKind
	group         string
	season        string
	seasonNumber  int
	episodeNumber int
	title         string
}

var (
	seasonDirRE  = regexp.MustCompile(`(?i)^season[ ._-]*(\d+)$`)
	seasonFileRE = regexp.MustCompile(`(?i)s(\d{1,3})e(\d{1,4})`)
)

func buildRecords(items []jobs.Job, moviesDir, tvDir string) []mediaRecord {
	records := make([]mediaRecord, 0, len(items))
	for _, job := range items {
		records = append(records, classify(job, moviesDir, tvDir))
	}
	return records
}

func classify(job jobs.Job, moviesDir, tvDir string) mediaRecord {
	r := mediaRecord{job: job, title: trimMediaExtension(filepath.Base(job.SourcePath)), seasonNumber: 1 << 30, episodeNumber: 1 << 30}
	if parts, ok := relativeParts(job.SourcePath, moviesDir); ok {
		r.kind = kindMovie
		r.group = r.title
		if len(parts) > 1 {
			r.group = parts[0]
		}
		return r
	}
	if parts, ok := relativeParts(job.SourcePath, tvDir); ok {
		r.kind = kindTV
		if len(parts) > 1 {
			r.group = parts[0]
		} else {
			r.group = r.title
		}
		for _, part := range parts[1:max(1, len(parts)-1)] {
			if match := seasonDirRE.FindStringSubmatch(part); len(match) == 2 {
				r.seasonNumber, _ = strconv.Atoi(match[1])
				r.season = "Season " + strconv.Itoa(r.seasonNumber)
				break
			}
			if strings.EqualFold(part, "specials") {
				r.season = "Specials"
			}
		}
		if match := seasonFileRE.FindStringSubmatch(r.title); len(match) == 3 {
			if r.season == "" {
				r.seasonNumber, _ = strconv.Atoi(match[1])
				r.season = "Season " + strconv.Itoa(r.seasonNumber)
			}
			r.episodeNumber, _ = strconv.Atoi(match[2])
		}
		if r.season == "" {
			r.season = "Other"
		}
		return r
	}
	r.group = filepath.Base(filepath.Dir(job.SourcePath))
	return r
}

func relativeParts(path, root string) ([]string, bool) {
	if root == "" {
		return nil, false
	}
	rel, err := filepath.Rel(filepath.Clean(root), filepath.Clean(path))
	if err != nil || rel == "." || rel == ".." || strings.HasPrefix(rel, ".."+string(filepath.Separator)) {
		return nil, false
	}
	return strings.Split(rel, string(filepath.Separator)), true
}

func trimMediaExtension(name string) string {
	return strings.TrimSuffix(name, filepath.Ext(name))
}

func naturalLess(a, b string) bool {
	aa, bb := []rune(strings.ToLower(a)), []rune(strings.ToLower(b))
	for i, j := 0, 0; i < len(aa) && j < len(bb); {
		if unicode.IsDigit(aa[i]) && unicode.IsDigit(bb[j]) {
			ii, jj := i, j
			for ii < len(aa) && unicode.IsDigit(aa[ii]) {
				ii++
			}
			for jj < len(bb) && unicode.IsDigit(bb[jj]) {
				jj++
			}
			an, _ := strconv.Atoi(string(aa[i:ii]))
			bn, _ := strconv.Atoi(string(bb[j:jj]))
			if an != bn {
				return an < bn
			}
			i, j = ii, jj
			continue
		}
		if aa[i] != bb[j] {
			return aa[i] < bb[j]
		}
		i++
		j++
	}
	return len(aa) < len(bb)
}

func sortRecords(records []mediaRecord) {
	sort.SliceStable(records, func(i, j int) bool {
		if records[i].seasonNumber != records[j].seasonNumber {
			return records[i].seasonNumber < records[j].seasonNumber
		}
		if records[i].episodeNumber != records[j].episodeNumber {
			return records[i].episodeNumber < records[j].episodeNumber
		}
		return naturalLess(records[i].title, records[j].title)
	})
}
