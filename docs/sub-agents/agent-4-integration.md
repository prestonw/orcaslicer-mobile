# Sub-Agent: Integration & AI Agent Pipeline Orchestrator
**Agent Role:** Sub-Agent 4
**Priority:** Phase 5 (final, depends on Phase 1-4)
**Status:** Ready

## Goal
Build the integration test suite, CI/CD pipeline, and AI agent orchestration layer for end-to-end validation.

## Deliverables
- `tests/e2e/slice-flow.test.ts` — End-to-end slice job test
- `tests/e2e/print-monitor.test.ts` — Printer monitoring integration test
- `tests/unit/slicing-service.test.ts` — Slicing service unit tests
- `tests/unit/printer-bridge.test.ts` — Printer bridge unit tests
- `.github/workflows/ci.yml` — CI/CD pipeline
- `.github/workflows/docker-build.yml` — Docker build on push
- `docs/api-contracts/` — OpenAPI/Swagger spec files
- `scripts/orchestrate-agents.sh` — Agent deployment script

## End-to-End Test Scenarios

### 1. Complete Slice Flow
```
1. Upload STL file via POST /api/v1/slice
2. Poll job status via WS /api/v1/jobs/{id}/status
3. Receive completed job with G-code file reference
4. Download generated G-code from /api/v1/jobs/{id}/download
5. Transfer G-code to printer via printer bridge
6. Start print job on printer
7. Monitor print progress until completion
```

### 2. Real-Time Monitoring
```
1. Connect to printer WebSocket via bridge
2. Subscribe to temperature, progress, and state events
3. Verify temperature graphs update in real-time
4. Verify progress percentage matches printer-reported value
5. Test pause/resume via WebSocket commands
```

### 3. Printer Discovery
```
1. Run mDNS discovery on test network
2. Verify printers with known hostnames are detected
3. Verify printer type classification (Moonraker vs OctoPrint)
4. Test manual IP entry fallback
5. Verify connection status updates on printer offline/online
```

## CI/CD Pipeline

### Build Stages
1. **Lint & Type Check** — ESLint, Prettier, Flutter analyze
2. **Unit Tests** — Jest (Node services), Flutter test
3. **Docker Build** — Validate slicing engine Dockerfile
4. **E2E Tests** — Spin up containers, run integration suite
5. **Release** — Tag + push Docker image + Flutter build artifacts

### GitHub Actions Workflows
- `ci.yml` — Run on every PR and push
- `docker-build.yml` — Build and push slicing engine Docker image
- `mobile-build.yml` — Build Flutter APK/IPA on tags

## AI Agent Orchestration

### Prompt Structure Template
Each sub-agent receives:
```yaml
agent_role: "<Role Name>"
priority: <1-5>
dependencies:
  - "<other agent role>"
deliverables:
  - "path/to/file"
test_command: "<command to verify deliverable>"
acceptance_criteria:
  - "<specific measurable outcome>"
constraints:
  - "<technical constraint>"
```

### Deployment Script
```bash
#!/bin/bash
# agents/orchestrate.sh
# Deploys and validates each sub-agent's work in dependency order
```

## Notes for AI Agent
- All e2e tests should be containerizable for CI
- Use `testcontainers` for spinning up test printer mock servers
- Generate OpenAPI spec from FastAPI auto-docs
- Flutter tests should cover widget tests + integration tests
- CI should run on GitHub Actions (free for public repos)
- Docker images should be pushed to GitHub Container Registry (GHCR)
