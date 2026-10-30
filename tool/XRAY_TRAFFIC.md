# Full JSON Xray traffic accounting

Full Xray JSON sessions use cumulative counters at the Android traffic entrance.
They do not sum outbound tags: a proxy chain can count the same data at several
outbounds, and user tags have no fixed `proxy`/`direct` meaning.

`CustomXrayConfig` enables `statsInboundUplink`/`statsInboundDownlink` in the
execution copy. Existing nonempty inbound tags, outbounds, routing, DNS and other
policy fields stay intact. Only untagged inputs receive unique tags, avoiding
existing tags and both array and comma-separated `routing.inboundTag` references.
The stored original and the external 256 KiB import limit do not change. The
bounded trusted-runtime validator allows room for previously added plumbing and
telemetry, so a valid near-limit original survives start-time revalidation.

## Accounting boundary

- VPN mode selects only the actual TUN tag. Auxiliary loopback inputs and
  chained outbounds are excluded, including when an outbound re-enters an
  auxiliary local proxy.
- Proxy mode selects the app's SOCKS 10808 and HTTP 10809 inputs. Explicit
  outbound loopback endpoints or freedom redirects back to either selected
  entrance, including known static DNS-host aliases, make this topology
  unavailable for accounting; its connection still runs. Adding known
  overlapping counters would not be a valid lower bound. Static exact/full/domain
  host rules and their explicit alias chains are checked; dynamic DNS and other
  resolver-specific graph changes are not proven by this local classification.
- Native selection uses exact JSON-encoded tag strings and exact counter names,
  preserving punctuation and Unicode. Missing counters, invalid selection,
  negative values or overflow produce an error rather than a valid zero.

These are Xray's logical entrance bytes, not interface/UID wire-byte estimates
or the server's subscription quota. TUN counts application connection/packet
payload. Local proxy input counters can include their local proxy handshake.
Outer transport overhead and traffic generated internally by other core
features are outside the TUN entrance measurement. Ordinary generated profiles
retain their existing outbound accounting contract.

## Sampling, reconnect and history

`XrayInboundTraffic` validates cumulative native snapshots and produces one delta
for `MeasuredTrafficLedger`. Repeating a snapshot adds zero; a failed read does
not advance the baseline, so a later valid read includes the intervening bytes.
Each new controller session starts with its own zero baseline. Independent probe
controllers never feed their counters into the active session ledger.

The stop API retains the selected counter references before native teardown,
then reads them after `core.Instance.Close`. The app records that final delta
before ending the ledger session. It does not reset counters while sampling.

Existing daily/monthly totals and historic partial flags remain. Missing historic
JSON usage cannot be reconstructed. Process death, failed persistence, clock/time
zone changes and a sample spanning midnight/month end keep the existing honest
partial/lower-bound rules; a boundary-spanning delta is not assigned to a guessed
date. `available=false` does not turn an unknown session into measured zero.

## Build and verification

`build_xray.ps1` and `build_xray_verify.py` rebuild and verify the additive native
API from wrapper commit `5bad0b55f2d002ace13657db11937bddcf48bc3b` and Xray commit
`3115a981a8b6`, using the original Go 1.26.7 toolchain. Enabling the pinned TUN
counter wrapper exposed an existing FullCone UDP issue: the plain connection
wrapper hides packet MultiBuffer methods and their per-packet destinations and
reply sources. A minimal declared compatibility patch preserves those interfaces
and counts successful packet writes, including partial failure. TCP behavior,
TLS policy and core version do not change. The verified core source is copied
into the workspace for this patch; the shared module cache remains untouched.
The build manifest records the exact inputs, base and patch hashes, local core
replacement, toolchain and output. All original AAR assets and the existing public
Java API must remain, and the old AAR is retained before replacement. See
`android/app/libs/README.md` for the final bundled artifact provenance.

Host entry points are `tool/test_multicore_profiles.ps1` and
`tool/native/test_xray_traffic.ps1`. Native regressions cover exact known-byte
transfers through chained outbounds, selected-input exclusion, reconnect,
cumulative reads, errors and counters growing during native close. The pinned
TUN handler regression exercises connection payload counting. These tests and
additional real-handler UDP regressions cover two packet destinations/reply
sources and successful-byte accounting on partial write failure. Tests and
ABI/API inspection do not establish a real Android TUN connection or provider
quota equivalence; live device networking is a separate check.
