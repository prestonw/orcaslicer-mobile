# OrcaSlicer Mobile

Open-source mobile 3D printing control application derived from OrcaSlicer. Designed as a decoupled architecture enabling automated AI coding agents to build, extend, and maintain the system.

## Overview

A mobile-first 3D printing control stack with:
- **Flutter mobile client** — real-time monitoring, G-code preview, camera streaming
- **Headless slicing engine** — OrcaSlicer CLI in Docker, REST API for mesh processing
- **Protocol bridge** — Moonraker/OctoPrint/Klipper integration via LAN
- **AI sub-agent orchestration** — structured task decomposition for automated development

## Architecture

| Component | Stack | Purpose |
|-----------|-------|---------|
| Mobile Frontend | Flutter/Dart | Cross-platform UI, print dashboard, 3D viewer |
| Slicing Engine | C++ CLI + Docker | Server-side G-code generation from STL/3MF |
| API Gateway | Node.js/Express | Auth, job queueing, WebSocket routing |
| Printer Bridge | Moonraker/OctoPrint API | LAN device discovery and control |

## Project Structure

```
orcaslicer-mobile/
├── docker/
│   └── slicing-engine/
│       ├── Dockerfile
│       └── slice-service/
├── mobile/
│   └── orcaslicer_app/
├── api/
│   └── gateway-service/
├── bridge/
│   └── printer-bridge/
├── docs/
│   ├── spec.md
│   └── sub-agents/
└── tests/
```

## Quick Start

1. Clone the repo
2. Build the slicing engine: `docker build -t orcaslicer-engine ./docker/slicing-engine/`
3. Start API gateway: `cd api/gateway-service && npm install && npm start`
4. Launch Flutter app: `cd mobile/orcaslicer_app && flutter run`

## Development

This project is structured for AI agent collaboration. Each subsystem is independently buildable and testable. See `docs/spec.md` for the full technical specification.

## License

MIT
