package libv2ray

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net"
	"testing"
	"time"

	appstats "github.com/xtls/xray-core/app/stats"
	core "github.com/xtls/xray-core/core"
	corestats "github.com/xtls/xray-core/features/stats"
)

type trafficCallbacks struct{}

func (trafficCallbacks) Startup() int                 { return 0 }
func (trafficCallbacks) Shutdown() int                { return 0 }
func (trafficCallbacks) OnEmitStatus(int, string) int { return 0 }

func assertTraffic(t *testing.T, raw string, up, down int64) {
	t.Helper()
	var got struct {
		Uplink   int64 `json:"uplink"`
		Downlink int64 `json:"downlink"`
	}
	if err := json.Unmarshal([]byte(raw), &got); err != nil {
		t.Fatal(err)
	}
	if got.Uplink != up || got.Downlink != down {
		t.Fatalf("traffic = %s, want uplink=%d downlink=%d", raw, up, down)
	}
}

func TestInboundTelemetryIsCumulativeAndDoesNotSumChains(t *testing.T) {
	m, _ := appstats.NewManager(context.Background(), &appstats.Config{})
	x := &CoreController{statsManager: m}
	for key, value := range map[string]int64{
		"inbound>>>unicode,;>>>tag>>>traffic>>>uplink":           31,
		"inbound>>>unicode,;>>>tag>>>traffic>>>downlink":         47,
		"outbound>>>chain-one>>>traffic>>>uplink":                31,
		"outbound>>>chain-two>>>traffic>>>uplink":                31,
		"inbound>>>auxiliary-proxy-reentry>>>traffic>>>uplink":   31,
		"inbound>>>auxiliary-proxy-reentry>>>traffic>>>downlink": 47,
	} {
		c, _ := m.RegisterCounter(key)
		c.Add(value)
	}
	for i := 0; i < 2; i++ {
		raw, err := x.QueryInboundTrafficStats(`["unicode,;>>>tag"]`)
		if err != nil {
			t.Fatal(err)
		}
		assertTraffic(t, raw, 31, 47)
	}
}

type closeTrafficFeature struct{ counter corestats.Counter }

func (*closeTrafficFeature) Type() interface{} { return (*closeTrafficFeature)(nil) }
func (*closeTrafficFeature) Start() error      { return nil }
func (f *closeTrafficFeature) Close() error    { f.counter.Add(83); return nil }

func TestFinalSnapshotIncludesBytesAddedDuringCoreClose(t *testing.T) {
	m, _ := appstats.NewManager(context.Background(), &appstats.Config{})
	up, _ := m.RegisterCounter("inbound>>>input>>>traffic>>>uplink")
	down, _ := m.RegisterCounter("inbound>>>input>>>traffic>>>downlink")
	up.Add(17)
	down.Add(29)
	inst, err := core.New(&core.Config{})
	if err != nil {
		t.Fatal(err)
	}
	if err := inst.AddFeature(&closeTrafficFeature{counter: down}); err != nil {
		t.Fatal(err)
	}
	x := &CoreController{CallbackHandler: trafficCallbacks{}, statsManager: m, coreInstance: inst, IsRunning: true}
	raw, err := x.StopLoopAndQueryInboundTrafficStats(`["input"]`)
	if err != nil {
		t.Fatal(err)
	}
	assertTraffic(t, raw, 17, 112)
	if x.statsManager != nil || x.coreInstance != nil || x.IsRunning {
		t.Fatal("shutdown state retained")
	}
}

func TestInvalidSelectionCannotPreventCoreShutdown(t *testing.T) {
	for _, selection := range []string{`[]`, `["input","input"]`, `[1]`, `["missing"]`} {
		m, _ := appstats.NewManager(context.Background(), &appstats.Config{})
		inst, err := core.New(&core.Config{})
		if err != nil {
			t.Fatal(err)
		}
		x := &CoreController{CallbackHandler: trafficCallbacks{}, statsManager: m, coreInstance: inst, IsRunning: true}
		if _, err := x.StopLoopAndQueryInboundTrafficStats(selection); err == nil {
			t.Fatal("invalid selection accepted")
		}
		if x.IsRunning || x.coreInstance != nil {
			t.Fatal("invalid telemetry prevented shutdown")
		}
	}
}

func TestUnavailableInboundTelemetryCannotReportZero(t *testing.T) {
	for _, x := range []*CoreController{{}, {statsManager: func() *appstats.Manager {
		m, _ := appstats.NewManager(context.Background(), &appstats.Config{})
		return m
	}()}} {
		if raw, err := x.QueryInboundTrafficStats(`["missing"]`); err == nil {
			t.Fatalf("unavailable telemetry reported %q", raw)
		}
	}
}

func TestInboundTelemetryRejectsOverflowAndNegativeCounters(t *testing.T) {
	for _, values := range [][]int64{{-1, 0}, {1 << 62, 1 << 62}} {
		m, _ := appstats.NewManager(context.Background(), &appstats.Config{})
		x := &CoreController{statsManager: m}
		for i, v := range values {
			c, _ := m.RegisterCounter(fmt.Sprintf("inbound>>>%d>>>traffic>>>uplink", i))
			c.Add(v)
			m.RegisterCounter(fmt.Sprintf("inbound>>>%d>>>traffic>>>downlink", i))
		}
		if _, err := x.QueryInboundTrafficStats(`["0","1"]`); err == nil {
			t.Fatal("invalid counter accepted")
		}
	}
}

func TestKnownBytesThroughChainedCoreAndFinalStop(t *testing.T) {
	echo, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	defer echo.Close()
	go func() {
		for {
			c, e := echo.Accept()
			if e != nil {
				return
			}
			go func() { defer c.Close(); io.Copy(c, c) }()
		}
	}()
	reserve, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	port := reserve.Addr().(*net.TCPAddr).Port
	reserve.Close()
	echoPort := echo.Addr().(*net.TCPAddr).Port
	config := fmt.Sprintf(`{"log":{"loglevel":"none"},"stats":{},"policy":{"system":{"statsInboundUplink":true,"statsInboundDownlink":true,"statsOutboundUplink":true,"statsOutboundDownlink":true}},"inbounds":[{"tag":"arbitrary,;>>>input","listen":"127.0.0.1","port":%d,"protocol":"dokodemo-door","settings":{"address":"127.0.0.1","port":%d,"network":"tcp"}}],"outbounds":[{"tag":"first,;exit","protocol":"freedom","proxySettings":{"tag":"second-exit","transportLayer":true}},{"tag":"second-exit","protocol":"freedom"}]}`, port, echoPort)
	x := NewCoreController(trafficCallbacks{})
	for session := 0; session < 2; session++ {
		if err := x.StartLoop(config, 0); err != nil {
			t.Fatal(err)
		}
		c, err := net.DialTimeout("tcp", fmt.Sprintf("127.0.0.1:%d", port), time.Second)
		if err != nil {
			t.Fatal(err)
		}
		c.SetDeadline(time.Now().Add(5 * time.Second))
		payload := bytes.Repeat([]byte{17, 23, 49, 0, 255}, 8192)
		if _, err := c.Write(payload); err != nil {
			t.Fatal(err)
		}
		got := make([]byte, len(payload))
		if _, err := io.ReadFull(c, got); err != nil {
			t.Fatal(err)
		}
		if !bytes.Equal(payload, got) {
			t.Fatal("echo bytes changed")
		}
		for sample := 0; sample < 2; sample++ {
			raw, err := x.QueryInboundTrafficStats(`["arbitrary,;>>>input"]`)
			if err != nil {
				t.Fatal(err)
			}
			assertTraffic(t, raw, int64(len(payload)), int64(len(payload)))
		}
		c.Close()
		raw, err := x.StopLoopAndQueryInboundTrafficStats(`["arbitrary,;>>>input"]`)
		if err != nil {
			t.Fatal(err)
		}
		assertTraffic(t, raw, int64(len(payload)), int64(len(payload)))
		if x.IsRunning {
			t.Fatal("core still running")
		}
		if _, err := x.StopLoopAndQueryInboundTrafficStats(`["arbitrary,;>>>input"]`); err == nil {
			t.Fatal("stopped telemetry unexpectedly reusable")
		}
	}
}
