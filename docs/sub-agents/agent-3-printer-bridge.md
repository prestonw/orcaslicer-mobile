# Sub-Agent: Network & Printer Protocol
**Agent Role:** Sub-Agent 3
**Priority:** Phase 4 (parallel with Phase 2-3)
**Status:** Ready

## Goal
Implement LAN-only printer communication layer with automatic discovery and multi-protocol support.

## Deliverables
- `bridge/printer-bridge/package.json` — Node.js/TypeScript project
- `bridge/printer-bridge/src/index.ts` — Entry point
- `bridge/printer-bridge/src/discovery.ts` — mDNS/Zeroconf printer discovery
- `bridge/printer-bridge/src/clients/moonraker.ts` — Moonraker/Klipper API client
- `bridge/printer-bridge/src/clients/octoprint.ts` — OctoPrint API client
- `bridge/printer-bridge/src/klipper-ws.ts` — Klipper WebSocket protocol handler
- `bridge/printer-bridge/src/jobs.ts` — Job state management and forwarding
- `bridge/printer-bridge/src/config.yaml` — Bridge configuration

## Key Requirements
1. **mDNS Discovery** — Auto-discover printers on LAN using `_http._tcp.local` service type
2. **Moonraker Support** — Full Moonraker API compatibility (klipper, machine, server, gcode files endpoints)
3. **OctoPrint Support** — OctoPrint REST API + WebSocket client
4. **WebSocket Streaming** — Subscribe to printer state changes in real-time
5. **Multi-Printer** — Track and manage multiple printers simultaneously
6. **LAN-Only** — No cloud dependency; all communication is local subnet
7. **Camera Streams** — Proxy/relay MJPEG and RTSP camera feeds from printers

## API Endpoints Exposed by Bridge
```
GET /api/printers              — List all discovered printers
GET /api/printers/:id/status   — Current printer state
GET /api/printers/:id/files    — G-code files on printer
POST /api/printers/:id/print   — Start print job
POST /api/printers/:id/cancel  — Cancel current job
POST /api/printers/:id/pause   — Pause current job
WS /api/printers/:id/events    — Real-time event stream
```

## Printer State Model
```typescript
interface PrinterState {
  id: string;
  name: string;
  type: 'moonraker' | 'octoprint';
  host: string;
  connected: boolean;
  status: 'idle' | 'printing' | 'paused' | 'error' | 'offline';
  hotend_temp: number;
  bed_temp: number;
  target_hotend: number;
  target_bed: number;
  progress: number; // 0-1
  print_time: number;
  eta: number;
  camera_url?: string;
  files: GCodeFile[];
}
```

## Notes for AI Agent
- Use `bonjour-service` for mDNS discovery on Linux
- OctoPrint API key via header: `X-Api-Key`
- Moonraker API: WebSocket + REST endpoints
- Klipper WebSocket protocol requires authentication via `PROTOSCL`
- Camera proxy should stream directly (no buffering)
- Handle printer reconnection with exponential backoff
- Cache printer config locally for offline resilience
