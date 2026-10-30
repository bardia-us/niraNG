package libbox

import (
	"encoding/binary"
	"encoding/json"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strconv"
	"testing"
	"time"

	"github.com/sagernet/sing-box/daemon"
)

// Exercise the actual pinned native parser/router/listener and verify that the
// additive binding neither overwrites active diagnostics nor leaves its port open.
func TestNirangProbeRoutingSnapshotAndClose(t *testing.T) {
	sBasePath = t.TempDir()
	sWorkingPath = t.TempDir()
	sTempPath = t.TempDir()
	sUserID = os.Getuid()
	sGroupID = os.Getgid()
	snapshot := filepath.Join(sBasePath, "configuration.json")
	if err := os.WriteFile(snapshot, []byte("retained-active-snapshot"), 0600); err != nil { t.Fatal(err) }
	activeCache := filepath.Join(sWorkingPath,"cache.db")
	if err := os.WriteFile(activeCache, []byte("retained-active-cache"), 0600); err != nil { t.Fatal(err) }
	privateCache,_ := json.Marshal(filepath.Join(t.TempDir(),"cache.db"))
	httpServer := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { w.WriteHeader(204) }))
	defer httpServer.Close()
	_, targetPortText, _ := net.SplitHostPort(httpServer.Listener.Addr().String())
	targetPort, _ := strconv.Atoi(targetPortText)
	reservation, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil { t.Fatal(err) }
	probePort := reservation.Addr().(*net.TCPAddr).Port
	reservation.Close()
	ctx := baseContext(nil)
	command := &CommandServer{ctx: ctx, StartedService: daemon.NewStartedService(daemon.ServiceOptions{Context: ctx, LogMaxLines: 0})}
	defer command.StartedService.Close()
	config := fmt.Sprintf(`{"log":{"disabled":true},"experimental":{"cache_file":{"path":%s}},"inbounds":[{"type":"socks","tag":"original-tun","listen":"127.0.0.1","listen_port":%d}],"outbounds":[{"type":"socks","tag":"dead","server":"127.0.0.1","server_port":1},{"type":"direct","tag":"direct"}],"route":{"final":"dead","rules":[{"inbound":["original-tun"],"port":[%d],"action":"route","outbound":"direct"}]}}`, privateCache,probePort,targetPort)
	if err := command.StartProbe(config); err != nil { t.Fatal(err) }
	defer command.CloseService()
	connection, err := net.DialTimeout("tcp",net.JoinHostPort("127.0.0.1",strconv.Itoa(probePort)),time.Second)
	if err != nil { t.Fatal(err) }
	defer connection.Close()
	connection.SetDeadline(time.Now().Add(3*time.Second))
	connection.Write([]byte{5,1,0})
	var greeting [2]byte
	if _,err := io.ReadFull(connection,greeting[:]); err != nil || greeting != [2]byte{5,0} { t.Fatalf("SOCKS greeting: %v %v",greeting,err) }
	request := []byte{5,1,0,1,127,0,0,1,0,0}
	binary.BigEndian.PutUint16(request[8:],uint16(targetPort))
	connection.Write(request)
	var reply [10]byte
	if _,err := io.ReadFull(connection,reply[:]); err != nil || reply[1] != 0 { t.Fatalf("SOCKS routing: %v %v",reply,err) }
	connection.Write([]byte("GET / HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n"))
	var status [12]byte
	if _,err := io.ReadFull(connection,status[:]); err != nil || string(status[:]) != "HTTP/1.1 204" { t.Fatalf("HTTP status: %q %v",status,err) }
	retained,err := os.ReadFile(snapshot)
	if err != nil || string(retained) != "retained-active-snapshot" { t.Fatal("Probe changed active diagnostic snapshot") }
	retained,err = os.ReadFile(activeCache)
	if err != nil || string(retained) != "retained-active-cache" { t.Fatal("Probe changed active cache") }
	connection.Close()
	if err := command.CloseService(); err != nil { t.Fatal(err) }
	rebound,err := net.Listen("tcp",net.JoinHostPort("127.0.0.1",strconv.Itoa(probePort)))
	if err != nil { t.Fatalf("Probe listener survived closeService: %v",err) }
	rebound.Close()
}
