package libv2ray

import (
	"encoding/json"
	"errors"
	"math"

	corestats "github.com/xtls/xray-core/features/stats"
)

// inboundCounterPair retains counters across core shutdown, which clears the
// manager. No reset-on-read or outbound counter is involved.
type inboundCounterPair struct{ uplink, downlink corestats.Counter }

func (x *CoreController) inboundTrafficCounters(tagsJSON string) ([]inboundCounterPair, error) {
	if x.statsManager == nil {
		return nil, errors.New("inbound telemetry unavailable")
	}
	var tags []string
	if len(tagsJSON) > 1<<20 || json.Unmarshal([]byte(tagsJSON), &tags) != nil || len(tags) == 0 || len(tags) > 1024 {
		return nil, errors.New("invalid inbound telemetry selection")
	}
	pairs := make([]inboundCounterPair, 0, len(tags))
	seen := make(map[string]bool, len(tags))
	for _, tag := range tags {
		if tag == "" || seen[tag] {
			return nil, errors.New("invalid inbound telemetry selection")
		}
		seen[tag] = true
		prefix := "inbound>>>" + tag + ">>>traffic>>>"
		pair := inboundCounterPair{x.statsManager.GetCounter(prefix + "uplink"), x.statsManager.GetCounter(prefix + "downlink")}
		if pair.uplink == nil || pair.downlink == nil {
			return nil, errors.New("selected inbound telemetry unavailable")
		}
		pairs = append(pairs, pair)
	}
	return pairs, nil
}

func encodeInboundTraffic(pairs []inboundCounterPair) (string, error) {
	var uplink, downlink int64
	for _, pair := range pairs {
		up, down := pair.uplink.Value(), pair.downlink.Value()
		if up < 0 || down < 0 || math.MaxInt64-uplink < up || math.MaxInt64-downlink < down {
			return "", errors.New("invalid inbound telemetry counter")
		}
		uplink += up
		downlink += down
	}
	raw, err := json.Marshal(struct {
		Uplink   int64 `json:"uplink"`
		Downlink int64 `json:"downlink"`
	}{uplink, downlink})
	return string(raw), err
}

// QueryInboundTrafficStats reads cumulative real byte counters at selected input
// boundaries. Tags are JSON encoded to preserve punctuation and Unicode exactly.
// The app selects its TUN in VPN mode, or its local proxy inputs in proxy mode;
// auxiliary internal re-entry inputs and chained outbounds are never summed.
func (x *CoreController) QueryInboundTrafficStats(tagsJSON string) (string, error) {
	x.coreMutex.Lock()
	defer x.coreMutex.Unlock()
	pairs, err := x.inboundTrafficCounters(tagsJSON)
	if err != nil {
		return "", err
	}
	return encodeInboundTraffic(pairs)
}

// StopLoopAndQueryInboundTrafficStats preserves StopLoop's shutdown/callback
// behavior, then reads retained counter references after coreInstance.Close.
// Even invalid/unavailable telemetry must not prevent the core from stopping.
func (x *CoreController) StopLoopAndQueryInboundTrafficStats(tagsJSON string) (string, error) {
	x.coreMutex.Lock()
	defer x.coreMutex.Unlock()
	pairs, err := x.inboundTrafficCounters(tagsJSON)
	if x.IsRunning {
		x.doShutdown()
		x.CallbackHandler.Shutdown()
		x.CallbackHandler.OnEmitStatus(0, "Core stopped")
	}
	if err != nil {
		return "", err
	}
	return encodeInboundTraffic(pairs)
}
