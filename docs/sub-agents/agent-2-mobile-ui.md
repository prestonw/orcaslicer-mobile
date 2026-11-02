# Sub-Agent: Mobile UI & 3D Viewer
**Agent Role:** Sub-Agent 2
**Priority:** Phase 3 (depends on Phase 2 API spec)
**Status:** Ready

## Goal
Build the Flutter mobile client for OrcaSlicer with 3D model viewing, print control, and camera streaming.

## Deliverables
- `mobile/orcaslicer_app/pubspec.yaml` — Project dependencies
- `mobile/orcaslicer_app/lib/main.dart` — App entry point
- `mobile/orcaslicer_app/lib/screens/` — Screen definitions (home, slice, monitor, settings)
- `mobile/orcaslicer_app/lib/widgets/` — Reusable UI components (temperature graph, progress meter, etc.)
- `mobile/orcaslicer_app/lib/models/` — Data models (Job, Printer, SliceProfile, etc.)
- `mobile/orcaslicer_app/lib/services/` — API client, WebSocket manager, local storage
- `mobile/orcaslicer_app/lib/providers/` — State management (Riverpod or Provider)

## Key Requirements
1. Cross-platform Flutter app (iOS + Android)
2. STL/3D model file viewer using `model_viewer_plus` or custom Three.js integration
3. Slicing parameter input forms (layer height, infill, temperature, speed)
4. Real-time print status dashboard with animated progress indicators
5. Temperature history graphs (hotend, bed)
6. Camera stream player supporting MJPEG and RTSP protocols
7. Responsive layout for phone and tablet
8. Dark/light theme support

## UI/UX Standards
- Follow Material 3 design guidelines
- Dark theme as default (reduces screen glare in print environments)
- Large touch targets for use with gloves
- Haptic feedback on critical actions (start, pause, emergency stop)
- Offline-first where possible (cache last-known printer state)

## State Management
- Use Riverpod for reactive state management
- WebSocket service for real-time printer updates
- Local storage (shared_preferences + Hive) for preferences and cached profiles

## Notes for AI Agent
- Target Flutter 3.x (stable channel)
- Add dependencies: `http`, `web_socket_channel`, `camera`, `video_player`, `charts_flutter`, `model_viewer_plus`
- API base URL should be configurable (ENV or settings screen)
- Handle connection loss gracefully with retry logic
- Implement file picker for STL/3MF import from device storage
