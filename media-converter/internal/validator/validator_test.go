package validator

import "testing"

func TestDurationMatches(t *testing.T) {
	for _, x := range []struct {
		a, b float64
		ok   bool
	}{{100, 101.9, true}, {100, 102.1, false}, {3600, 3635, true}, {3600, 3637, false}, {0, 99, true}} {
		if got := DurationMatches(x.a, x.b); got != x.ok {
			t.Errorf("DurationMatches(%v,%v)=%v", x.a, x.b, got)
		}
	}
}
