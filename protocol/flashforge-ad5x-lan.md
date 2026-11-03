# Flashforge AD5X LAN Protocol (reverse-engineered, verified live)

Source: tcpdump capture `printer-handshake.pcap` (2026-11-02, 3 real upload
attempts of a 25.25 MB gcode) + live probe while the printer was BUILDING.

## Transport

- TCP **8899**, raw serial-over-TCP. NOT HTTP, NOT OctoPrint (port 80 is
  refused; 8898 answers 404/empty to HTTP and is not the protocol port).
- Framing (verified byte-for-byte from the capture):
  - status/query commands: `~Mxxx\r\n\n` (CRLF + blank line)
  - `~M28` and `~M23`: `~Mxxx ...\n` (single LF only)
  - Both framings are accepted by the printer; CRLF works for everything
    (tested live: M119/M105 with \r\n\n).
- Every response ends with a line `ok\r\n` (printer uses CRLF).
- Flash Studio uses **short-lived connections: one per phase** —
  M601+M115+M640+M119 on one connection; M28+data on a second; M29 on a
  third; M23 on a fourth. M29/M23 connections carry ONLY the command
  (no M601 handshake).
- `~M640` is sent after M115; response `CMD M640 \r\n\n Received.\r\nok\r\n`
  (purpose unclear, harmless).

## Handshake (must precede everything on a new connection)

```
send: ~M601 S1\n\n
recv: CMD M601 Received.\r\nControl Success V2.1.\r\nok\r\n
```
"Control failed." = handshake rejected (reconnect + retry).

## Machine identification — M115

```
send: ~M115\n\n
recv: CMD M115 Received.\r\n
      Machine Type: Flashforge AD5X\r\n
      Machine Name: AD5X\r\n
      Firmware: v3.1.7\r\n
      SN: SNMQQF9101617\r\n
      X: 220 Y: 220 Z: 220\r\n
      Tool Count: 1\r\n
      Mac Address:24:A1:0D:B4:7C:EA \r\n
      ok\r\n
```
Use Machine Type/Name to confirm a scanned 8899 endpoint is an AD5X
(replaces the current `scanLocalNetwork()` port-80 probe → probe 8899 and
M115).

## Status polling — M119 (Flash Studio polls this every ~5s)

```
send: ~M119\n\n
recv (idle):    MachineStatus: READY     MoveMode: READY   Status: S:0 L:0 J:0 F:0  LED: 1  CurrentFile: (empty)
recv (printing):MachineStatus: BUILDING  MoveMode: MOVING  Status: S:1 L:0 J:0 F:0  LED: 1  CurrentFile: Body15_PLA_6h6m.gcode
```
Fields: MachineStatus, MoveMode, Status flags (S/L/J/F), LED (on=1),
CurrentFile.

The printing reply also carries build-plate endstops (verified live):

```
Endstop: X-max: 110 Y-max: 110 Z-min: 0
```

## Print progress — M27 (safe read-only while BUILDING)

```
send: ~M27\n\n
recv: CMD M27 Received.\r\nSD printing byte 65/100\r\nLayer: 374/674\r\nok\r\n
```
`byte N/100` is a real 0–100 percentage (NOT raw bytes), `Layer: n/total`
is the live layer. No time field — remaining time must be estimated:
total duration comes from the gcode header
(`; estimated printing time (normal mode) = 6h 5m 49s`) or the filename
token (`6h6m`), remaining = total × (1 − progress). The printer's own
2h25m readout matches this model (verified 2026-11-03: ~61% → est 2h24m).

## File upload (verified: 25,462,xxx → done + selected)

```
1. ~M28 <bytes> 0:/user/<name>.gcode\n\n
   → CMD M28 Received.\r\nWriting to file: /usr/data/gcodes/<name>.gcode\r\nok\r\n
2. stream raw gcode bytes (no framing, no per-chunk acks).
   NOTE: printer writes to SD slowly (~0.4-1.2 MB/s); 25 MB takes 20-60 s.
   Do NOT apply a read timeout to the socket during this phase.
3. ~M29\n\n
   → CMD M29 Received.\r\nDone saving file.\r\nok\r\n
4. ~M23 0:/user/<name>.gcode\n\n
   → CMD M23 Received.\r\nFile opened: <name>.gcode Size: 26462629\r\nFile selected\r\nok\r\n
```
`<bytes>` in M28 is the exact file size in decimal. Printer renames to
`/usr/data/gcodes/<name>.gcode` regardless of the `/user/` path given.

### The mid-upload drop (why Flash Studio's own uploads flake)

Captured attempts at the same file: died at 0.41 MB (1.6%), died at 22.61 MB
(89.5%), succeeded at full size. No RSTs, no retransmissions — the CLIENT
gives up mid-write (its own timeout while the printer slowly absorbs data)
and retries on a fresh connection. Mobile app rule: generous/no write-phase
timeout; one retry on drop is normal and succeeds.

## Still unknown (probe only when NOT printing — control codes mid-BUILDING are risky)

- LED/light toggle (M119 reports `LED: 1`; control command unknown)
- print start (post-select: M24 or Flashforge variant?)
- print stop / pause
- M640 (sent after M115; response is a bare ok, purpose unclear — possibly
  "enter command mode")
