package apskit

import "testing"

func TestMetadataFilename(t *testing.T) {
	cases := []struct {
		in, want string
	}{
		{"features/Hunt The Wumpus.feature", "features-hunt-the-wumpus-feature.json"},
		{"features/orders/Cancel Order.feature", "features-orders-cancel-order-feature.json"},
		{"Features/API v2/Happy Path.feature", "features-api-v2-happy-path-feature.json"},
	}
	for _, c := range cases {
		if got := MetadataFilename(c.in); got != c.want {
			t.Errorf("MetadataFilename(%q) = %q, want %q", c.in, got, c.want)
		}
	}
}
