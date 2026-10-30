"""Generate explicit overlays without altering the verified pinned module cache."""
import hashlib,json,pathlib,sys
project,core,output=map(pathlib.Path,sys.argv[1:4])
output.mkdir(parents=True,exist_ok=True)
handler=core/'proxy/tun/handler.go'
tests=core/'proxy/tun/handler_test.go'
original=handler.read_bytes()
patched=original.decode()
fix=project/'tool/native/xray/tun_udp_counter.go.txt'
if fix.exists():
    old='''conn = &stat.CounterConnection{
			Connection:   conn,
			ReadCounter:  t.uplinkCounter,
			WriteCounter: t.downlinkCounter,
		}'''
    new='''if udp, ok := conn.(*udpConn); ok {
			conn = &telemetryUDPConnection{udpConn: udp, uplink: t.uplinkCounter, downlink: t.downlinkCounter}
		} else {
			conn = &stat.CounterConnection{
				Connection: conn, ReadCounter: t.uplinkCounter, WriteCounter: t.downlinkCounter,
			}
		}'''
    assert patched.count(old)==1,'Pinned TUN handler differs from reviewed source'
    patched=patched.replace(old,new)+fix.read_text()
handler_out=output/'handler.go';handler_out.write_text(patched)
test_out=output/'handler_test.go';test_out.write_bytes(tests.read_bytes()+(project/'tool/native/xray/tun_udp_traffic_test.go.txt').read_bytes())
overlay={'Replace':{str(handler.resolve()):str(handler_out.resolve()),str(tests.resolve()):str(test_out.resolve())}}
(output/'overlay.json').write_text(json.dumps(overlay))
metadata={'coreBaseHandlerSha256':hashlib.sha256(original).hexdigest(),'handlerOverlaySha256':hashlib.sha256(handler_out.read_bytes()).hexdigest(),'testOverlaySha256':hashlib.sha256(test_out.read_bytes()).hexdigest(),'coreVersionUnchanged':True,'moduleCacheUnmodified':True}
(output/'overlay-metadata.json').write_text(json.dumps(metadata,indent=2))
print(json.dumps(metadata))
