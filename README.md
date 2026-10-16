# vid_downloader_app

A new Flutter project.

## Backend and app setup

1. Install and start the Flask backend from the repository root:

   ```powershell
   python -m pip install -r backend/requirements.txt
   $env:VIDSAVE_API_KEY = "your-private-key"
   python backend/server.py
   ```

   The backend listens on port `8787` and must be reachable by the device.
   Keep the API key private and configure the same value in the app's **Daha
   Fazlası → Backend bağlantısı** settings.

2. In the app, enter the backend address and optional API key, then choose
   **Bağlantıyı Sına ve Kaydet**. The URL and key are stored using platform
   encrypted storage.

3. Use an address reachable from the device:
   - Android emulator: `http://10.0.2.2:8787`
   - Physical phone: `http://<computer-LAN-IP>:8787` while both are on the same
     network (debug build only)
   - Production: use an HTTPS hostname/reverse proxy. Android release builds
     intentionally reject cleartext HTTP.

Set `VIDSAVE_MAX_DOWNLOAD_BYTES` on the backend to change the default maximum
stream size (4 GiB). A key stored on a user's device is not secret from that
device's owner; use per-user or short-lived credentials for distributed apps.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
