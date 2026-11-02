# OrcaSlicer Mobile — Technical Specification

## 1. Executive Summary

This technical specification sheet outlines an actionable, rapid-turnaround architecture for building an open-source mobile 3D printing control application derived from OrcaSlicer. Designed specifically to guide automated AI coding agents (e.g., Hermes), this specification focuses exclusively on achievable, decoupled technical implementations rather than desktop framework porting.

## 2. System Architecture & Core Stack

### 2.1 Mobile Frontend
- **Framework:** Flutter / Dart (Cross-platform)
- **Purpose:** Lightweight UI for mobile devices, print status dashboard, G-code previewer, camera stream player
- **Platforms:** iOS and Android

### 2.2 Headless Slicing Engine
- **Runtime:** OrcaSlicer C++ CLI (Docker Container)
- **Purpose:** Server-side mesh processing, G-code generation, profile evaluation using CLI commands (`orca-slicer --slice`)
- **Deployment:** Linux container with GPU optional

### 2.3 API Gateway / Router
- **Framework:** Node.js / Express / FastAPI
- **Purpose:** REST API and WebSocket server handling client authentication, job queueing, and network routing to printers

### 2.4 Printer Protocol Bridge
- **Protocols:** Moonraker / OctoPrint APIs & WebSockets
- **Purpose:** Direct TCP/HTTP communication for local LAN monitoring, streaming MJPEG/H.264 camera feeds, and job control

## 3. Key Actionable Components

### 3.1 Headless Slicing Microservice

**Implementation:**
1. Package the compiled desktop C++ OrcaSlicer CLI binary into a Linux Docker container
2. Expose REST endpoints (`/api/v1/slice`) accepting STL/3MF file uploads along with JSON-formatted slicing profile parameters
3. Execute CLI slice jobs asynchronously, returning output G-code path and estimated print metadata (time, filament weight)

**API Contract:**
```
POST /api/v1/slice
Content-Type: multipart/form-data
Body: {
  model: File (STL/3MF),
  profile: JSON (slicing parameters),
  priority: number (optional, default 5)
}

Response (202 Accepted):
{
  "job_id": "uuid",
  "status": "queued",
  "estimated_time_seconds": 1800,
  "filament_weight_grams": 45.2
}

WS /api/v1/jobs/:job_id/status
{
  "job_id": "uuid",
  "status": "slicing",
  "progress": 0.45,
  "eta_seconds": 1020
}
```

### 3.2 Native Mobile Client Application

**Components:**
- **Model Viewer:** 3D STL file viewing component via Three.js / Flutter 3D package
- **Print Control Dashboard:** Real-time temperature graphs, progress meters, and axis movement controls
- **Video Monitor:** Low-latency camera display via HTTP MJPEG stream or RTSP
- **Profile Selector:** Filament and print profile override selection sent during slice requests

### 3.3 Local Network (LAN-Only) Communication Engine

**Capabilities:**
- Auto-discover printers on local subnet using mDNS / Zeroconf (`_http._tcp.local`)
- Direct HTTP REST and WebSocket connections to Moonraker/Klipper and OctoPrint endpoints bypassing external cloud brokers
- Fallback to direct IP entry if auto-discovery fails

## 4. Sub-Agent Work Breakdown & Task Allocation

### Sub-Agent 1: Headless Engine & Containerization
**Responsibility:** Build and containerize the slicing service
**Tasks:**
- Build Dockerfile compiling headless OrcaSlicer CLI on Ubuntu base
- Create Python FastAPI wrapper handling `/slice` requests and returning generated G-code files
- Implement job queue with priority support (Redis or in-memory)
- Add health check and graceful shutdown

**Deliverables:**
- `docker/slicing-engine/Dockerfile`
- `docker/slicing-engine/slice-service/main.py`
- `docker/slicing-engine/slice-service/config.yaml`

### Sub-Agent 2: Mobile UI & 3D Viewer Developer
**Responsibility:** Build the Flutter client
**Tasks:**
- Implement Flutter cross-platform UI shell for iOS and Android
- Integrate 3D STL mesh viewing canvas
- Build slicing parameter input forms
- Implement real-time status dashboard with temperature graphs
- Add camera stream player (MJPEG/RTSP)

**Deliverables:**
- `mobile/orcaslicer_app/lib/main.dart`
- `mobile/orcaslicer_app/lib/screens/`
- `mobile/orcaslicer_app/lib/widgets/`
- `mobile/orcaslicer_app/lib/models/`
- `mobile/orcaslicer_app/lib/services/`

### Sub-Agent 3: Network & Printer Protocol Specialist
**Responsibility:** Printer communication layer
**Tasks:**
- Develop Moonraker, OctoPrint, and Klipper API client integrations for local network monitoring
- Implement mDNS local discovery service for automatic printer IP detection
- Build WebSocket connection pool for real-time updates
- Implement printer health monitoring and alerting

**Deliverables:**
- `bridge/printer-bridge/src/discovery.ts`
- `bridge/printer-bridge/src/clients/moonraker.ts`
- `bridge/printer-bridge/src/clients/octoprint.ts`
- `bridge/printer-bridge/src/klipper-ws.ts`

### Sub-Agent 4: Integration & AI Agent Pipeline Orchestrator
**Responsibility:** End-to-end integration and automation
**Tasks:**
- Create automated test suite verifying end-to-end flow: STL upload → Cloud slice → G-code transport → Printer execution
- Generate prompt structures and context specs for Hermes deployment
- Build CI/CD pipeline for automated testing and deployment
- Document API contracts and integration points

**Deliverables:**
- `tests/e2e/slice-flow.test.ts`
- `tests/e2e/print-monitor.test.ts`
- `docs/api-contracts/`
- CI configuration files

## 5. Technical Constraints

- **No desktop framework porting** — focus on mobile-only, server-side slicing
- **LAN-first architecture** — printers discovered locally, no cloud dependency for control
- **Docker containerized slicing** — isolate resource-heavy C++ compilation
- **AI-agent friendly** — clear task boundaries, independent submodules, structured specs
- **Open source** — MIT license, public repository

## 6. Build Order & Dependencies

```
Phase 1: Headless Slicing Engine (Sub-Agent 1)
  ↓
Phase 2: API Gateway (Sub-Agent 4)
  ↓
Phase 3: Mobile Client (Sub-Agent 2) ← depends on Phase 2 API spec
  ↓
Phase 4: Printer Bridge (Sub-Agent 3) ← parallel with Phase 2-3
  ↓
Phase 5: Integration Testing (Sub-Agent 4)
```

## 7. Monitoring & Observability

- **Slicing Engine:** Prometheus metrics for job queue depth, slice duration, error rate
- **Mobile Client:** Crash reporting, user action analytics, print success rate
- **Printer Bridge:** Connection health, discovery latency, message delivery success
- **API Gateway:** Request latency, authentication failures, rate limiting

## 8. Security Considerations

- JWT-based authentication for mobile-to-API communication
- LAN-only printer communication (no external exposure)
- Rate limiting on slicing endpoints to prevent abuse
- Input validation on all file uploads (STL/3MF)
- Certificate pinning for optional cloud features
