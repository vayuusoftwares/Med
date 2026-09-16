# 🚀 Release Build Checklist

## ✅ Pre-Build Verification

### 1. Backend Configuration
- [x] **ngrok URL configured**: `https://overjoyed-strode-bountiful.ngrok-free.dev`
- [x] **AppConfig set to use ngrok**: `useNgrok = true` in `lib/app_config.dart`
- [x] **All screens use AppConfig**: home_screen, task_screen, admin screens ✓
- [x] **ngrok headers added**: `ngrok-skip-browser-warning: true` in AppConfig.headers

### 2. Database Setup
**IMPORTANT: Run these PHP files in your browser BEFORE testing the app:**

1. **Setup database and tables**:
   ```
   http://localhost/backend/setup_db.php
   ```
   This creates: users, doctors, clinics, tasks, order_pdfs, attendance_history, **fetch_loc**

2. **Migrate user data** (if you have old `sales_user` and `admin_user` tables):
   ```
   http://localhost/backend/migrate_users.php
   ```
   This merges old separate tables into the unified `users` table with role field.

3. **Migrate doctor/clinic data** (if needed):
   ```
   http://localhost/backend/migrate_doctors_clinics.php
   ```

### 3. ngrok Tunnel
**Make sure ngrok is running:**
```bash
ngrok http 80
```
- The tunnel URL must match `AppConfig.ngrokUrl`
- The tunnel must stay open while testing

### 4. WAMP Configuration
- [ ] **WAMP is running**
- [ ] **MySQL is accessible** (green light in WAMP tray icon)
- [ ] **Database `medsafe_db` exists** with all tables

---

## 🔨 Build the APK

### Option 1: Debug APK (faster, for testing)
```bash
cd "e:\Freeansing\projects\MedsafeLifeScience\Android\medsafelifescience"
flutter build apk --debug
```

### Option 2: Release APK (optimized, smaller size)
```bash
cd "e:\Freeansing\projects\MedsafeLifeScience\Android\medsafelifescience"
flutter build apk --release
```

---

## 📦 Install APK

### APK Location:
- **Debug**: `build/app/outputs/flutter-apk/app-debug.apk`
- **Release**: `build/app/outputs/flutter-apk/app-release.apk`

### Transfer to Phone:
1. **USB**: Connect phone → copy APK → install
2. **Email**: Attach APK → open on phone → install
3. **Cloud**: Upload to Drive/Dropbox → download on phone → install

### Android Settings:
- Enable **"Install from Unknown Sources"** in phone settings
- Some phones require per-app permission (e.g., Chrome, Files app)

---

## 🧪 Testing Checklist

### Sales Rep Login:
- [ ] Login with sales rep credentials
- [ ] Check-in (GPS location captured)
- [ ] View dashboard with pending tasks
- [ ] Click "Continue Task" — map shows route from current → destination
- [ ] Complete task
- [ ] Check-out

### Admin Login:
- [ ] Login with admin credentials
- [ ] View sales rep list with Active/Inactive status
- [ ] Click **ℹ️ About** button — shows rep details in bottom sheet
- [ ] Click "Track" button — opens live tracking map
- [ ] View attendance history tab

### Map & GPS:
- [ ] Current location marker appears (blue with pulse animation)
- [ ] Destination marker appears (red)
- [ ] Route path draws correctly (not just straight line)
- [ ] Polyline follows roads

### Task Assignment (Admin):
- [ ] Create new task with known doctor/clinic
- [ ] Create new task with unknown doctor — manual entry works
- [ ] Task appears in sales rep's pending list
- [ ] Map URL from Google Maps is parsed correctly

---

## ⚠️ Important Notes

1. **ngrok URL Changes**: If you restart ngrok, the URL changes. You must:
   - Update `AppConfig.ngrokUrl` in Flutter
   - Rebuild the APK
   - Reinstall on phone

2. **Free ngrok Limitations**:
   - Only 1 tunnel at a time
   - URL changes on restart
   - 40 requests/minute limit

3. **Location Tracking**:
   - The app pushes GPS location every 5 seconds when a task is active
   - Admin can see live location in `fetch_loc` table
   - Location is shown in the "About" bottom sheet

4. **Offline Mode**:
   - The app requires internet connection
   - GPS works offline, but backend sync needs internet

5. **Database Access**:
   - ngrok tunnels HTTP requests to your local WAMP
   - Your MySQL must be accessible to WAMP's Apache
   - Default MySQL port is 3306

---

## 🐛 Troubleshooting

### "Connection failed" error:
- [ ] Check ngrok tunnel is running
- [ ] Verify ngrok URL in `AppConfig.ngrokUrl`
- [ ] Check WAMP is running
- [ ] Test backend: `https://your-ngrok-url.ngrok-free.dev/backend/login.php`

### Map not showing route:
- [ ] GPS permission granted on phone
- [ ] Location services enabled
- [ ] Task has valid source and destination coordinates
- [ ] Check `get_route.php` returns polyline data

### Pending task popup not appearing:
- [ ] Task exists with `status='pending'` in database
- [ ] Task belongs to logged-in user (matching `user_id`)
- [ ] Sales rep is checked in (not admin)

### "About" button not showing rep details:
- [ ] Rep has location data in `fetch_loc` table
- [ ] GPS tracking was enabled in the app
- [ ] Location was pushed within last 24 hours

---

## 📝 Post-Installation

### First Launch:
1. Grant location permissions when prompted
2. Grant storage permissions (for PDFs)
3. Login with test credentials
4. Verify home screen loads

### Test Account Credentials:
```
Sales Rep:
Email: abikrishna@medsafe.com
Password: (your password)

Admin:
Email: admin@medsafe.com
Password: (your password)
```

---

## ✅ Ready to Install

If all checklist items are verified:
- [x] AppConfig has correct ngrok URL
- [x] ngrok tunnel is running
- [x] Database tables are created
- [x] WAMP is running
- [ ] APK is built
- [ ] APK is installed on phone

**You are ready to install and test!** 🎉
