# Sub-Agent: Headless Engine & Containerization
**Agent Role:** Sub-Agent 1
**Priority:** Phase 1 (first, blocks downstream work)
**Status:** Ready

## Goal
Build and containerize the OrcaSlicer headless slicing engine with FastAPI service.

## Deliverables
- `docker/slicing-engine/Dockerfile` — Ubuntu-based container with OrcaSlicer CLI
- `docker/slicing-engine/slice-service/main.py` — FastAPI REST API for slicing
- `docker/slicing-engine/slice-service/config.yaml` — Slicing configuration
- `docker/slicing-engine/slice-service/jobs.py` — Job queue management
- `docker/slicing-engine/slice-service/models.py` — Request/response schemas

## Key Requirements
1. Compile OrcaSlicer CLI as headless binary (no GUI dependencies)
2. Accept multipart/form-data with STL/3MF uploads
3. Parse JSON slicing profile from request body
4. Execute `orca-slicer --slice` asynchronously
5. Return job status via WebSocket or polling endpoint
6. Support priority queuing for concurrent slice jobs

## API Contract Reference
See `docs/spec.md` section 3.1 for full API specification.

## Notes for AI Agent
- Start from Ubuntu 22.04 or 24.04 base image
- OrcaSlicer source available at `https://github.com/SoftFever/OrcaSlicer`
- Headless build may require: `cmake -DBUILD_TESTS=OFF -DBUILD_GUI=OFF`
- Install only essential GUI libs (for dependency resolution), then strip
- Container should expose port 8000 for FastAPI service
- Add health check endpoint: `GET /health`
- Use `redis` or in-memory queue with TTL for job management
- Generate G-code to `/data/gcode/{job_id}.gcode` with cleanup policy
