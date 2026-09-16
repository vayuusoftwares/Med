# MedsafeLifeScience — Development Network Configuration (NGROK HTTPS + WAMP + MySQL)

This repository contains the complete **Flutter Android Application** connected to the existing **WAMP Server Backend (Apache + PHP / MySQL `medsafe_db`)** exposed via **NGROK HTTPS Tunnel**.

---

## 🏗️ Architecture Overview

```
┌─────────────────────────┐
│   Flutter Android App   │
└────────────┬────────────┘
             │ HTTPS
             ▼
┌─────────────────────────┐
│    NGROK Public URL     │
│   (HTTPS Secure Tunnel) │
└────────────┬────────────┘
             │ http://localhost:80
             ▼
┌─────────────────────────┐
│   WAMP Apache / PHP     │
│ (C:\wamp64\www\backend) │
└────────────┬────────────┘
             │ localhost:3306
             ▼
┌─────────────────────────┐
│   Existing MySQL DB     │
│  (medsafe_db + Data)    │
└─────────────────────────┘
```

---

## 🛠️ 1. Requirements

- **Operating System**: Windows PC
- **Web Server**: WAMPServer (Apache on Port 80, MySQL on Port 3306)
- **Database**: MySQL (`medsafe_db`) with all tables and data
- **Public Tunnel**: NGROK CLI (`ngrok`)
- **Mobile Development**: Flutter SDK (3.x+)

---

## 🗄️ 2. Database & WAMP Server Setup

The existing MySQL database `medsafe_db` is preserved with all tables and data intact.

### Database Credentials
- **Host**: `localhost` (127.0.0.1)
- **Port**: `3306`
- **Database Name**: `medsafe_db`
- **User**: `root`
- **Password**: `""` *(empty string)*

### Starting WAMP
1. Start **WAMPServer** from the Windows Start menu or desktop shortcut.
2. Ensure the WAMP tray icon is green (Apache on Port 80 and MySQL on Port 3306 are running).

---

## 🌐 3. NGROK HTTPS Tunnel Setup

Expose the local WAMP Apache web server to the internet securely via HTTPS using NGROK.

```powershell
# 1. Start NGROK tunnel pointing to WAMP Apache port (80):
ngrok http 80
```

NGROK will print a public HTTPS URL, for example:
`https://overjoyed-strode-bountiful.ngrok-free.dev`

---

## 📱 4. Flutter Android Configuration

The Flutter app configuration is centralized in [`lib/app_config.dart`](file:///e:/projects/Freeansing/projects/MedsafeLifeScience/Android/medsafelifescience/lib/app_config.dart).

```dart
class AppConfig {
  // ── 1. NGROK HTTPS Development Tunnel URL ──────────────────────────────────
  static const String ngrokUrl = 'https://overjoyed-strode-bountiful.ngrok-free.dev';

  // ── 2. Your PC / Server local IP ──────────────────────────────────────────
  static const String localIp = 'http://10.0.2.2';

  // ── 3. Toggle: true = use NGROK tunnel ────────────────────────────────────
  static const bool useNgrok = true;
  ...
}
```

Whenever a new NGROK URL is generated:
1. Copy the HTTPS URL from the `ngrok` console output.
2. Open [`lib/app_config.dart`](file:///e:/projects/Freeansing/projects/MedsafeLifeScience/Android/medsafelifescience/lib/app_config.dart).
3. Update `ngrokUrl` with the new URL.

---

## 🚀 5. Complete System Startup Sequence

To run the entire stack on your Windows PC:

1. **Start WAMPServer**:
   Ensure Apache (port `80`) and MySQL (port `3306`) are running.
2. **Verify Local API**:
   Test endpoint: `http://127.0.0.1/backend/get_data.php`
3. **Start NGROK Tunnel**:
   ```powershell
   ngrok http 80
   ```
4. **Update Flutter App Base URL**:
   Paste the NGROK HTTPS URL into `lib/app_config.dart` (`ngrokUrl`).
5. **Run Flutter Mobile Application**:
   ```powershell
   flutter run
   ```

---

## 🔧 6. Troubleshooting Guide

| Issue | Cause | Solution |
| :--- | :--- | :--- |
| **MySQL connection refused** | MySQL service stopped | Start WAMPServer or ensure `mysqld` is running on port 3306 |
| **Apache not running** | Port 80 conflict / WAMP stopped | Check WAMP Apache status in WAMP tray menu |
| **NGROK Session Expired / Reconnect** | Tunnel closed | Run `ngrok http 80` and update `lib/app_config.dart` |
| **Flutter Connection Failed** | Outdated URL in `AppConfig` | Copy current NGROK HTTPS URL into `lib/app_config.dart` |

