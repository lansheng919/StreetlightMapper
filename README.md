# StreetlightMapper

> iPhone application for field technicians to capture **Pole ID ↔ Street Light** associations using the device camera, with offline support and REST/SAP integration.

---

## Requirements

| Tool | Version |
|------|---------|
| Xcode | 15+ |
| iOS Deployment Target | 16.0+ |
| Swift | 5.9 |
| [XcodeGen](https://github.com/yonaskolb/XcodeGen) | 2.x (project generation) |

Install XcodeGen:
```bash
brew install xcodegen
```

---

## Getting Started

```bash
# 1. Generate the .xcodeproj
cd StreetlightMapper
xcodegen generate

# 2. Open in Xcode
open StreetlightMapper.xcodeproj
```

Set your Apple Developer **Team ID** in `project.yml` → `DEVELOPMENT_TEAM`, then build and run on a **physical iPhone** (camera is required — the simulator has no camera).

---

## Project Structure

```
StreetlightMapper/
├── Models/
│   └── CaptureModels.swift         # CaptureSession, StreetLightEntry, Confidence, SyncStatus, DTOs
├── Persistence/
│   └── SessionStore.swift          # JSON-backed local store + photo storage
├── Services/
│   ├── CameraManager.swift         # AVFoundation + Vision (OCR & QR)
│   ├── ConnectivityMonitor.swift   # NWPathMonitor wrapper
│   └── SyncService.swift           # Offline queue + SAP upload
├── Server/
│   └── MockSAPServer.swift         # Embedded HTTP server (port 8080)
├── ViewModels/
│   ├── CaptureViewModel.swift      # Shared scan/capture state + auto-capture logic
│   └── WorkflowViewModel.swift     # Multi-step workflow coordinator
├── Views/
│   ├── Capture/
│   │   ├── CameraPreviewView.swift # AVCaptureVideoPreviewLayer + reticle overlay
│   │   ├── PoleIDCaptureView.swift # OCR capture screen
│   │   └── StreetLightCaptureView.swift  # QR code scan screen
│   ├── Session/
│   │   ├── SessionReviewView.swift # Per-session review before submission
│   │   └── SessionListView.swift   # All captured sessions + detail
│   ├── Debug/
│   │   └── DebugView.swift         # Integration test / mock SAP console
│   ├── Supporting/
│   │   └── ActionButtonStyle.swift
│   └── ContentView.swift           # Tab bar root
├── Resources/
│   └── Info.plist
└── StreetlightMapperApp.swift      # @main entry point
```

---

## Feature Overview

### 1. Pole ID Capture (OCR)
- Live camera feed with a framed reticle.
- Apple **Vision** `VNRecognizeTextRequest` runs at ~5 fps and surfaces the highest-confidence text candidate.
- **Green overlay + auto-capture** when confidence ≥ 80 %.
- **Yellow overlay + manual entry prompt** when confidence < 80 %.
- Technician can edit the detected text and confirm — photo is then captured.

### 2. Street Light QR Capture
- `VNDetectBarcodesRequest` targets QR, Code 128, and Data Matrix symbologies.
- Same confidence/auto-capture logic as Pole ID.
- Header shows a running count of street lights captured for the current pole.

### 3. Pole ↔ Street Light Association
- One **CaptureSession** holds one Pole ID and `[StreetLightEntry]`.
- Technician can add unlimited street lights per session before submitting.
- **SessionReviewView** shows:
  - Pole ID + capture quality badge (AUTO / VERIFIED / MANUAL).
  - List of all street lights with individual confidence badges.
  - Pole photo thumbnail (if captured).

### 4. Local Storage
- `SessionStore` persists sessions as JSON in the app's **Documents** directory.
- Photos saved as JPEG under `Documents/photos/`.
- No external dependencies — no CoreData schema migrations needed.

### 5. REST API — Mock SAP Server
An embedded HTTP server (built on `Network.framework`'s `NWListener`) starts automatically on **port 8080**.

| Method | Path | Description |
|--------|------|-------------|
| `GET`  | `/api/v1/health` | Returns `{"status":"ok"}` |
| `GET`  | `/api/v1/sessions` | All sessions received by the mock |
| `GET`  | `/api/v1/sessions/:id` | Single session by UUID |
| `POST` | `/api/v1/sessions` | Accept a `SessionDTO` payload |

**Test from your Mac (same network):**
```bash
# Replace <iPhone-IP> with the device's LAN IP
curl http://<iPhone-IP>:8080/api/v1/health
curl http://<iPhone-IP>:8080/api/v1/sessions
```

**Point at a real SAP endpoint:**  
Set the `SAP_BASE_URL` environment variable (Xcode scheme → Arguments → Environment Variables) or change the default in [`SyncService.swift`](StreetlightMapper/Services/SyncService.swift):
```
SAP_BASE_URL = https://your-sap-host/api/v1
```

### 6. Offline Support & Sync
- `ConnectivityMonitor` (NWPathMonitor) tracks network state.
- **Saving never uploads.** A saved capture is stored on the phone as `syncStatus = .pending`; syncing is a separate action the technician does now or later.
- Sync from **Home** (*Sync All Now*), the **History** toolbar (*Sync All*), a capture's detail page (*Sync This Capture*), or the review screen right after saving (*Sync Now*). Sync buttons are disabled while offline.
- Optional **Auto-sync when online** toggle (Integration tab, off by default) uploads queued captures automatically when the network returns.
- Failed uploads are marked `.failed` and retried on the next sync.

### 7. Deleting captures
- A capture that has **not reached the server** (pending or failed) can be deleted from the review screen, its History detail page, or by swiping in History. Its photos are deleted too, after a confirmation.
- Once a capture has been synced it cannot be deleted from the phone (the server would keep an orphan copy). This also applies if it is edited after syncing.
- To clear everything (including synced captures and photos) while testing, use **Integration → Delete All Captures**. It also clears the mock server's received list.

### 8. App icon
- The icon lives in `StreetlightMapper/Resources/Assets.xcassets/AppIcon.appiconset` (a single 1024×1024 image; Xcode generates the other sizes).
- It is drawn by [`tools/make_icon.swift`](tools/make_icon.swift). To change it, edit that script and run `swift tools/make_icon.swift StreetlightMapper/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png`, or drop in your own opaque 1024×1024 PNG with the same name.

---

## Integration Test Workflow (no SAP required)

1. Launch the app on an iPhone.
2. Tap **Integration** tab — the mock server should show "Running ✓".
3. Complete a capture session and save it.
4. Tap **Sync All Now** on Home (or **Sync Now** after saving) — the session is `POST`ed to the embedded server.
5. The **Received by Mock Server** list updates with the session.
6. From a Mac on the same Wi-Fi, verify with curl:
   ```bash
   curl http://<iPhone-IP>:8080/api/v1/sessions | python3 -m json.tool
   ```

---

## Confidence Threshold

The auto-capture threshold is defined in [`CaptureViewModel.swift`](StreetlightMapper/ViewModels/CaptureViewModel.swift):

```swift
let kHighConfidenceThreshold: Float = 0.80
```

Adjust this value to tune the balance between automation and verification prompts.

---

## Privacy / Permissions

The app requests:
- **Camera** — for pole label OCR and QR scanning.
- **Local Network** — to expose the embedded REST server on the LAN.

Both are declared in `Info.plist` with usage descriptions as required by App Store review.

---

## Extending to Production

| Concern | Recommendation |
|---------|----------------|
| Database | Replace JSON store with CoreData or SQLite (GRDB) for large fleets |
| Authentication | Add OAuth 2.0 / SAP SSO token to `SyncService` request headers |
| Photo upload | Stream photos as multipart/form-data or upload to S3 separately |
| Pole ID format | Add a regex validator in `CaptureViewModel` to filter OCR noise |
| QR symbology | Extend `request.symbologies` if devices use other barcode types |
| Conflict resolution | Implement ETag / last-write-wins in `SyncService.uploadSession` |
