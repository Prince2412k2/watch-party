package jobs

import "time"

const (
	Discovered        = "discovered"
	Queued            = "queued"
	Probing           = "probing"
	Remuxing          = "remuxing"
	TranscodingAudio  = "transcoding_audio"
	TranscodingVideo  = "transcoding_video"
	Validating        = "validating"
	Completed         = "completed"
	Failed            = "failed"
	Cancelled         = "cancelled"
	Skipped           = "skipped"
	RequiresTranscode = "requires_transcode"
)

type Job struct {
	ID                                                                 int64 `json:"id"`
	SourcePath, TargetPath, TempPath, MediaType, Status, OperationType string
	Priority                                                           int
	VideoCodec, AudioCodecs, SubtitleCodecs                            string
	SourceSize, TargetSize                                             int64
	Duration, Progress                                                 float64
	FFmpegSpeed                                                        string
	CreatedAt                                                          time.Time
	StartedAt, CompletedAt                                             *time.Time
	AttemptCount                                                       int
	ErrorMessage, Notes, FFmpegStderr                                  string
	CancelRequested, DryRun                                            bool
}

func Active(status string) bool {
	switch status {
	case Queued, Probing, Remuxing, TranscodingAudio, TranscodingVideo, Validating:
		return true
	}
	return false
}
