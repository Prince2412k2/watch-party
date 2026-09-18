package storage

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"time"

	"github.com/snuffkin/media-converter/internal/jobs"
	_ "modernc.org/sqlite"
)

type Store struct{ db *sql.DB }

func Open(path string) (*Store, error) {
	db, err := sql.Open("sqlite", path+"?_pragma=busy_timeout(5000)&_pragma=journal_mode(WAL)&_pragma=foreign_keys(1)")
	if err != nil {
		return nil, err
	}
	db.SetMaxOpenConns(8)
	s := &Store{db: db}
	if err = s.migrate(); err != nil {
		db.Close()
		return nil, err
	}
	return s, nil
}
func (s *Store) Close() error { return s.db.Close() }
func (s *Store) migrate() error {
	_, err := s.db.Exec(`
CREATE TABLE IF NOT EXISTS jobs (
 id INTEGER PRIMARY KEY AUTOINCREMENT, source_path TEXT NOT NULL UNIQUE, target_path TEXT NOT NULL, temp_path TEXT NOT NULL,
 media_type TEXT NOT NULL DEFAULT 'unknown', status TEXT NOT NULL, priority INTEGER NOT NULL DEFAULT 50, operation_type TEXT NOT NULL DEFAULT '',
 video_codec TEXT NOT NULL DEFAULT '', audio_codecs TEXT NOT NULL DEFAULT '', subtitle_codecs TEXT NOT NULL DEFAULT '',
 source_size INTEGER NOT NULL DEFAULT 0, target_size INTEGER NOT NULL DEFAULT 0, duration REAL NOT NULL DEFAULT 0,
 progress REAL NOT NULL DEFAULT 0, ffmpeg_speed TEXT NOT NULL DEFAULT '', created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
 started_at DATETIME, completed_at DATETIME, attempt_count INTEGER NOT NULL DEFAULT 0, error_message TEXT NOT NULL DEFAULT '',
 notes TEXT NOT NULL DEFAULT '', ffmpeg_stderr TEXT NOT NULL DEFAULT '', cancel_requested INTEGER NOT NULL DEFAULT 0, dry_run INTEGER NOT NULL DEFAULT 0
);
CREATE INDEX IF NOT EXISTS idx_jobs_queue ON jobs(status, priority, created_at);
CREATE TABLE IF NOT EXISTS settings (key TEXT PRIMARY KEY, value TEXT NOT NULL);
INSERT OR IGNORE INTO settings(key,value) VALUES('paused','false');`)
	return err
}

func (s *Store) Add(ctx context.Context, j jobs.Job) (bool, error) {
	status := j.Status
	if status == "" {
		status = jobs.Queued
	}
	mediaType := j.MediaType
	if mediaType == "" {
		mediaType = "unknown"
	}
	r, err := s.db.ExecContext(ctx, `INSERT OR IGNORE INTO jobs(source_path,target_path,temp_path,media_type,status,priority,source_size,dry_run,error_message,notes,completed_at) VALUES(?,?,?,?,?,?,?,?,?,?,CASE WHEN ? IN ('skipped','failed') THEN CURRENT_TIMESTAMP ELSE NULL END)`, j.SourcePath, j.TargetPath, j.TempPath, mediaType, status, j.Priority, j.SourceSize, j.DryRun, j.ErrorMessage, j.Notes, status)
	if err != nil {
		return false, err
	}
	n, _ := r.RowsAffected()
	return n == 1, nil
}
func (s *Store) Claim(ctx context.Context) (jobs.Job, error) {
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return jobs.Job{}, err
	}
	defer tx.Rollback()
	row := tx.QueryRowContext(ctx, `SELECT `+columns+` FROM jobs WHERE status=? ORDER BY priority ASC, created_at ASC, id ASC LIMIT 1`, jobs.Queued)
	j, err := scan(row)
	if err != nil {
		return jobs.Job{}, err
	}
	now := time.Now()
	r, err := tx.ExecContext(ctx, `UPDATE jobs SET status=?,started_at=?,attempt_count=attempt_count+1,error_message='',cancel_requested=0 WHERE id=? AND status=?`, jobs.Probing, now, j.ID, jobs.Queued)
	if err != nil {
		return jobs.Job{}, err
	}
	n, _ := r.RowsAffected()
	if n != 1 {
		return jobs.Job{}, sql.ErrNoRows
	}
	j.Status = jobs.Probing
	j.StartedAt = &now
	j.AttemptCount++
	if err = tx.Commit(); err != nil {
		return jobs.Job{}, err
	}
	return j, nil
}

const columns = `id,source_path,target_path,temp_path,media_type,status,priority,operation_type,video_codec,audio_codecs,subtitle_codecs,source_size,target_size,duration,progress,ffmpeg_speed,created_at,started_at,completed_at,attempt_count,error_message,notes,ffmpeg_stderr,cancel_requested,dry_run`

type scanner interface{ Scan(...any) error }

func scan(r scanner) (jobs.Job, error) {
	var j jobs.Job
	var started, completed sql.NullTime
	err := r.Scan(&j.ID, &j.SourcePath, &j.TargetPath, &j.TempPath, &j.MediaType, &j.Status, &j.Priority, &j.OperationType, &j.VideoCodec, &j.AudioCodecs, &j.SubtitleCodecs, &j.SourceSize, &j.TargetSize, &j.Duration, &j.Progress, &j.FFmpegSpeed, &j.CreatedAt, &started, &completed, &j.AttemptCount, &j.ErrorMessage, &j.Notes, &j.FFmpegStderr, &j.CancelRequested, &j.DryRun)
	if started.Valid {
		j.StartedAt = &started.Time
	}
	if completed.Valid {
		j.CompletedAt = &completed.Time
	}
	return j, err
}
func (s *Store) Get(ctx context.Context, id int64) (jobs.Job, error) {
	return scan(s.db.QueryRowContext(ctx, `SELECT `+columns+` FROM jobs WHERE id=?`, id))
}
func (s *Store) List(ctx context.Context, limit int) ([]jobs.Job, error) {
	if limit <= 0 {
		limit = 200
	}
	rows, err := s.db.QueryContext(ctx, `SELECT `+columns+` FROM jobs ORDER BY CASE WHEN status IN ('probing','remuxing','transcoding_audio','transcoding_video','validating') THEN 0 WHEN status='queued' THEN 1 ELSE 2 END,priority,COALESCE(completed_at,created_at) DESC LIMIT ?`, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []jobs.Job
	for rows.Next() {
		j, e := scan(rows)
		if e != nil {
			return nil, e
		}
		out = append(out, j)
	}
	return out, rows.Err()
}
func (s *Store) UpdateState(ctx context.Context, id int64, status, operation, errMsg, notes, stderr string) error {
	_, err := s.db.ExecContext(ctx, `UPDATE jobs SET status=?,operation_type=CASE WHEN ?='' THEN operation_type ELSE ? END,error_message=?,notes=CASE WHEN ?='' THEN notes ELSE ? END,ffmpeg_stderr=CASE WHEN ?='' THEN ffmpeg_stderr ELSE ? END,completed_at=CASE WHEN ? IN ('completed','failed','cancelled','skipped','requires_transcode') THEN CURRENT_TIMESTAMP ELSE completed_at END WHERE id=?`, status, operation, operation, errMsg, notes, notes, stderr, stderr, status, id)
	return err
}
func (s *Store) SetProbe(ctx context.Context, id int64, video, audio, subs string, duration float64) error {
	_, e := s.db.ExecContext(ctx, `UPDATE jobs SET video_codec=?,audio_codecs=?,subtitle_codecs=?,duration=? WHERE id=?`, video, audio, subs, duration, id)
	return e
}
func (s *Store) Progress(ctx context.Context, id int64, p float64, speed string, size int64) error {
	_, e := s.db.ExecContext(ctx, `UPDATE jobs SET progress=?,ffmpeg_speed=?,target_size=? WHERE id=?`, p, speed, size, id)
	return e
}
func (s *Store) MarkConflict(ctx context.Context, source string) error {
	_, e := s.db.ExecContext(ctx, `UPDATE jobs SET status=?,error_message='target MP4 already exists',notes='conflict',completed_at=CURRENT_TIMESTAMP WHERE source_path=? AND status<>?`, jobs.Skipped, source, jobs.Completed)
	return e
}
func (s *Store) Finish(ctx context.Context, id int64, size int64) error {
	_, e := s.db.ExecContext(ctx, `UPDATE jobs SET status=?,progress=100,target_size=?,completed_at=CURRENT_TIMESTAMP,cancel_requested=0 WHERE id=?`, jobs.Completed, size, id)
	return e
}
func (s *Store) Priority(ctx context.Context, id int64, p int) error {
	r, e := s.db.ExecContext(ctx, `UPDATE jobs SET priority=? WHERE id=? AND status=?`, p, id, jobs.Queued)
	if e == nil {
		if n, _ := r.RowsAffected(); n == 0 {
			return fmt.Errorf("job %d is not queued", id)
		}
	}
	return e
}
func (s *Store) Cancel(ctx context.Context, id int64) error {
	r, e := s.db.ExecContext(ctx, `UPDATE jobs SET cancel_requested=1,status=CASE WHEN status=? THEN ? ELSE status END,completed_at=CASE WHEN status=? THEN CURRENT_TIMESTAMP ELSE completed_at END WHERE id=? AND status IN (?,?,?,?,?,?)`, jobs.Queued, jobs.Cancelled, jobs.Queued, id, jobs.Queued, jobs.Probing, jobs.Remuxing, jobs.TranscodingAudio, jobs.TranscodingVideo, jobs.Validating)
	if e == nil {
		if n, _ := r.RowsAffected(); n == 0 {
			return fmt.Errorf("job %d cannot be cancelled", id)
		}
	}
	return e
}
func (s *Store) CancelRequested(ctx context.Context, id int64) bool {
	var b bool
	_ = s.db.QueryRowContext(ctx, `SELECT cancel_requested FROM jobs WHERE id=?`, id).Scan(&b)
	return b
}
func (s *Store) Retry(ctx context.Context, id int64) error {
	r, e := s.db.ExecContext(ctx, `UPDATE jobs SET status=?,progress=0,ffmpeg_speed='',error_message='',completed_at=NULL,cancel_requested=0 WHERE id=? AND status IN (?,?,?,?)`, jobs.Queued, id, jobs.Failed, jobs.Cancelled, jobs.Skipped, jobs.RequiresTranscode)
	if e == nil {
		if n, _ := r.RowsAffected(); n == 0 {
			return fmt.Errorf("job %d is not retryable", id)
		}
	}
	return e
}
func (s *Store) SetPaused(ctx context.Context, v bool) error {
	_, e := s.db.ExecContext(ctx, `INSERT INTO settings(key,value) VALUES('paused',?) ON CONFLICT(key) DO UPDATE SET value=excluded.value`, fmt.Sprint(v))
	return e
}
func (s *Store) Paused(ctx context.Context) bool {
	var v string
	_ = s.db.QueryRowContext(ctx, `SELECT value FROM settings WHERE key='paused'`).Scan(&v)
	return v == "true"
}
func (s *Store) Recover(ctx context.Context) ([]jobs.Job, error) {
	rows, e := s.db.QueryContext(ctx, `SELECT `+columns+` FROM jobs WHERE status IN (?,?,?,?,?)`, jobs.Probing, jobs.Remuxing, jobs.TranscodingAudio, jobs.TranscodingVideo, jobs.Validating)
	if e != nil {
		return nil, e
	}
	defer rows.Close()
	var out []jobs.Job
	for rows.Next() {
		j, e := scan(rows)
		if e != nil {
			return nil, e
		}
		out = append(out, j)
	}
	_, e = s.db.ExecContext(ctx, `UPDATE jobs SET status=?,error_message='recovered after interrupted process',progress=0,ffmpeg_speed='',cancel_requested=0 WHERE status IN (?,?,?,?,?)`, jobs.Queued, jobs.Probing, jobs.Remuxing, jobs.TranscodingAudio, jobs.TranscodingVideo, jobs.Validating)
	return out, e
}
func (s *Store) Counts(ctx context.Context) (map[string]int, error) {
	rows, e := s.db.QueryContext(ctx, `SELECT status,count(*) FROM jobs GROUP BY status`)
	if e != nil {
		return nil, e
	}
	defer rows.Close()
	m := map[string]int{}
	for rows.Next() {
		var k string
		var n int
		if e = rows.Scan(&k, &n); e != nil {
			return nil, e
		}
		m[k] = n
	}
	return m, rows.Err()
}
func IsNotFound(err error) bool { return errors.Is(err, sql.ErrNoRows) }
