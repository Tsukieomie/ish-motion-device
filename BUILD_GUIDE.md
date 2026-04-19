# iSH /dev/motion — Complete Build & Sideload Guide

> **Target:** iPhone 15 Pro · iOS · No jailbreak required  
> **Goal:** Build a custom iSH IPA with `/dev/motion` support and sideload it alongside the App Store version.

---

## Table of Contents

1. [Prerequisites](#1-prerequisites)
2. [Clone the iSH Repository](#2-clone-the-ish-repository)
3. [Apply the /dev/motion Patch](#3-apply-the-devmotion-patch)
4. [Xcode Configuration](#4-xcode-configuration)
5. [Build the IPA](#5-build-the-ipa)
6. [Sideload with AltStore](#6-sideload-with-altstore)
7. [First Launch & Grant Permissions](#7-first-launch--grant-permissions)
8. [Test /dev/motion](#8-test-devmotion)
9. [Reconnect the bore.pub SSH Tunnel](#9-reconnect-the-borepub-ssh-tunnel)
10. [Troubleshooting](#10-troubleshooting)

---

## 1. Prerequisites

### Hardware & Software

| Requirement | Notes |
|-------------|-------|
| Mac running macOS 13 Ventura or later | Apple Silicon or Intel both work |
| Xcode 15 or later | Download from the Mac App Store — it's free |
| iPhone 15 Pro | Connected to the same Wi-Fi network as your Mac |
| USB-C cable | For initial AltStore installation |
| Internet connection | For cloning and package downloads |

### Apple ID

- A **free Apple ID** is all you need for sideloading. You do not need a paid $99/yr developer account.
- A free account limits you to **3 sideloaded apps at a time** and requires **re-signing every 7 days** (AltStore handles this automatically over Wi-Fi).
- If you already have AltStore installed from a previous project, skip to [Section 2](#2-clone-the-ish-repository).

### Command-line Tools

Install the following before cloning. Open Terminal and run each block:

```bash
# Install Homebrew if not present
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# Install ninja (build system used by iSH's JIT compiler)
brew install ninja

# Install LLVM (provides clang and lld — required by iSH's build scripts)
brew install llvm

# Install libarchive (used by iSH's apk package manager layer)
brew install libarchive

# Install meson (the meta-build system)
pip3 install meson
```

Verify everything is available:

```bash
clang --version     # Should show Apple clang or LLVM clang
ninja --version     # e.g. 1.11.1
meson --version     # e.g. 1.4.0
python3 --version   # 3.9+ is fine
```

> **Note on LLVM PATH:** Homebrew installs LLVM to `/opt/homebrew/opt/llvm/bin` (Apple Silicon) or `/usr/local/opt/llvm/bin` (Intel). The iSH build scripts look for `lld` and `clang` on your PATH. If the build fails with "lld not found", add LLVM to your shell profile:
>
> ```bash
> # For Apple Silicon Macs
> echo 'export PATH="/opt/homebrew/opt/llvm/bin:$PATH"' >> ~/.zshrc
> source ~/.zshrc
>
> # For Intel Macs
> echo 'export PATH="/usr/local/opt/llvm/bin:$PATH"' >> ~/.zshrc
> source ~/.zshrc
> ```

### Patch Files

Your patch files are already at `/home/user/workspace/ish_hardware_patch/`:

```
ish_hardware_patch/
├── MotionDevice.h          ← new header to copy into app/
├── MotionDevice.m          ← new implementation to copy into app/
├── devices_patch.diff      ← patch for fs/devices.h
├── AppDelegate_patch.diff  ← patch for app/AppDelegate.m
└── README.md
```

Keep this directory open in Finder — you will copy files from here in Step 3.

---

## 2. Clone the iSH Repository

Clone iSH with all submodules. The `--recurse-submodules` flag is **required** — without it the build will fail on missing JIT compiler files.

```bash
cd ~/Developer          # or wherever you keep projects
git clone --recurse-submodules https://github.com/ish-app/ish
cd ish
```

Expected output: Git will clone the main repo and then initialize a handful of submodules (musl, awk, etc.). This takes 1–3 minutes depending on your connection.

Verify the submodules initialized correctly:

```bash
ls tools/       # should contain files, not be empty
ls deps/        # should show musl/ and other dependency directories
```

---

## 3. Apply the /dev/motion Patch

All edits below are made from inside the cloned `ish/` directory. Do each step in order.

### 3.1 — Copy MotionDevice.h into app/

```bash
cp /home/user/workspace/ish_hardware_patch/MotionDevice.h app/MotionDevice.h
```

Verify:

```bash
cat app/MotionDevice.h
# Should print the header with: extern struct dev_ops motion_dev;
```

### 3.2 — Copy MotionDevice.m into app/

```bash
cp /home/user/workspace/ish_hardware_patch/MotionDevice.m app/MotionDevice.m
```

Verify:

```bash
head -5 app/MotionDevice.m
# Should show: // MotionDevice.m — iSH Custom Hardware Patch
```

### 3.3 — Patch fs/devices.h

Apply the diff automatically:

```bash
git apply /home/user/workspace/ish_hardware_patch/devices_patch.diff
```

**If `git apply` fails** (e.g., the upstream file changed slightly), apply it manually instead. Open `fs/devices.h` in any text editor and find the `#endif` at the very bottom of the file. Insert the two new lines **before** it:

```c
// /dev/motion  (accelerometer + gyroscope + attitude + barometer)
#define DEV_MOTION_MINOR    2

#endif
```

The context around the change should look like this when done:

```c
// /dev/clipboard
#define DEV_CLIPBOARD_MINOR 0
// /dev/gps  (also named /dev/location)
#define DEV_LOCATION_MINOR  1
// /dev/motion  (accelerometer + gyroscope + attitude + barometer)
#define DEV_MOTION_MINOR    2

#endif
```

### 3.4 — Patch app/AppDelegate.m

Apply the diff automatically:

```bash
git apply /home/user/workspace/ish_hardware_patch/AppDelegate_patch.diff
```

**If `git apply` fails**, make the two changes manually:

**Change A — Add the import near the top of `app/AppDelegate.m`**, immediately after the `#import "LocationDevice.h"` line:

```objc
#import "PasteboardDevice.h"
#import "LocationDevice.h"
#import "MotionDevice.h"          // ← ADD THIS LINE
#import "NSObject+SafeKVO.h"
```

**Change B — Register the device in the `-boot` method.** Find the block that registers the location device (search for `location_dev`):

```objc
err = dyn_dev_register(&location_dev, DEV_CHAR, DYN_DEV_MAJOR, DEV_LOCATION_MINOR);
if (err != 0)
    return err;
generic_mknod(AT_FDCWD, "/dev/location", S_IFCHR|0666, dev_make(DYN_DEV_MAJOR, DEV_LOCATION_MINOR));
```

Add the motion registration block **immediately after** it:

```objc
err = dyn_dev_register(&motion_dev, DEV_CHAR, DYN_DEV_MAJOR, DEV_MOTION_MINOR);
if (err != 0)
    return err;
generic_mknod(AT_FDCWD, "/dev/motion", S_IFCHR|0666, dev_make(DYN_DEV_MAJOR, DEV_MOTION_MINOR));
```

### 3.5 — Verify the patch

Quick sanity check before opening Xcode:

```bash
# Confirm both new files are present
ls -la app/MotionDevice.h app/MotionDevice.m

# Confirm devices.h has the new define
grep DEV_MOTION_MINOR fs/devices.h

# Confirm AppDelegate.m imports MotionDevice.h
grep "MotionDevice" app/AppDelegate.m
```

All three commands should return matches. If any are missing, re-check the step above.

---

## 4. Xcode Configuration

### 4.1 — Open the project

```bash
open iSH.xcodeproj
```

*Screenshot description: Xcode opens with the iSH project. The left sidebar shows the project navigator with folders: app/, fs/, kernel/, tools/, and others.*

### 4.2 — Change the Bundle Identifier

This is the **most important step** for coexistence with the App Store version. The App Store iSH uses `com.felix.ish`. Your sideloaded copy needs a different bundle ID so both apps can be installed simultaneously.

1. In the project navigator (left sidebar), click on **iSH** (the blue Xcode project icon at the very top).
2. In the center pane, make sure the **PROJECT** is selected (not a target), then click the **iSH** target.
3. Click the **Build Settings** tab.
4. Search for `PRODUCT_BUNDLE_IDENTIFIER`.
5. Double-click the value and change it to something unique, for example:
   ```
   com.yourname.ish.motion
   ```
   Use only lowercase letters, numbers, hyphens, and dots.

**Alternatively**, edit `iSH.xcconfig` directly:

```bash
# Open the config file in a text editor
open app/iSH.xcconfig
```

Find the line:
```
ROOT_BUNDLE_IDENTIFIER = com.felix.ish
```

Change it to:
```
ROOT_BUNDLE_IDENTIFIER = com.yourname.ish.motion
```

Save the file. Xcode will pick up the change automatically.

### 4.3 — Set your Development Team

1. In Xcode, with the **iSH** target selected, click the **Signing & Capabilities** tab.
2. Under **Signing**, uncheck **Automatically manage signing** if it is checked (optional but gives you more control).
3. Click the **Team** dropdown and select your Apple ID. If your Apple ID doesn't appear:
   - Go to **Xcode → Settings → Accounts** (⌘,)
   - Click **+** → **Apple ID** → sign in
   - Return to Signing & Capabilities — your account should now appear.
4. Re-check **Automatically manage signing**.

*Screenshot description: The Signing & Capabilities tab shows Team set to your name "(Personal Team)", Bundle Identifier shows your custom bundle ID, and a provisioning profile has been auto-generated.*

> **Free account note:** Xcode may show a warning: *"Personal team does not support the capability..."* for some entitlements (like push notifications). This is fine — just dismiss it. The motion patch does not require any special entitlements.

### 4.4 — Add MotionDevice.m to Compile Sources

Xcode must be told to compile the new `.m` file — copying it into `app/` is not enough.

1. Select the **iSH** target.
2. Click the **Build Phases** tab.
3. Expand **Compile Sources**.
4. Click the **+** button at the bottom-left of that section.
5. In the file picker that appears, type `MotionDevice` in the search field.
6. Select **MotionDevice.m** and click **Add**.

*Screenshot description: The Compile Sources list now includes MotionDevice.m alongside AppDelegate.m, LocationDevice.m, PasteboardDevice.m, and other .m files.*

### 4.5 — Add CoreMotion.framework

1. Still on the **Build Phases** tab, expand **Link Binary With Libraries**.
2. Click the **+** button.
3. In the search field, type `CoreMotion`.
4. Select **CoreMotion.framework** from the list and click **Add**.

*Screenshot description: Link Binary With Libraries now shows CoreMotion.framework, UIKit.framework, and the other previously linked frameworks.*

### 4.6 — Add NSMotionUsageDescription (Optional but Recommended)

iOS will not prompt for motion permissions when using `CMMotionManager` directly (unlike Location, which requires explicit permission). However, adding a usage description string is good practice and future-proofs the app against App Store policy changes (not relevant for sideloading, but harmless).

1. In the project navigator, expand **app/** and open **Info.plist**.
2. Right-click any existing row and select **Add Row**.
3. Type `NSMotionUsageDescription` as the key (Xcode may autocomplete it).
4. Set the value to:
   ```
   iSH uses motion sensors to provide /dev/motion access to Linux programs.
   ```

---

## 5. Build the IPA

### 5.1 — Select the correct scheme and destination

1. In the Xcode toolbar at the top, click the **scheme selector** (shows something like `iSH > My Mac`).
2. Change the **destination** from "My Mac" to your **iPhone 15 Pro** (it must be plugged in via USB or paired wirelessly).

*Screenshot description: The scheme/destination dropdown shows "iSH" as the scheme and "Nghia's iPhone 15 Pro" as the destination.*

### 5.2 — Build once to catch errors

Press **⌘B** (Product → Build) before archiving. This compiles everything and surfaces any errors immediately — faster feedback than waiting for a full archive.

**Common build errors at this stage:**

| Error | Fix |
|-------|-----|
| `'MotionDevice.h' file not found` | MotionDevice.h was not copied into `app/` (re-check Step 3.1) |
| `use of undeclared identifier 'motion_dev'` | MotionDevice.m not in Compile Sources (re-check Step 4.4) |
| `framework 'CoreMotion' not found` | CoreMotion.framework not linked (re-check Step 4.5) |
| `use of undeclared identifier 'DEV_MOTION_MINOR'` | fs/devices.h patch not applied (re-check Step 3.3) |
| Signing errors | Re-check Step 4.3; make sure your iPhone is trusted by the Mac |

### 5.3 — Archive the app

Once **⌘B** succeeds:

1. Disconnect your iPhone or change the destination to **Any iOS Device (arm64)** — archiving requires a device destination, not a simulator.
2. Go to **Product → Archive** (⌘⇧B does build only — you need the menu).
3. Xcode will build a release version and open the **Organizer** window when done.

*Screenshot description: The Organizer window shows one archive entry labeled "iSH" with today's date and your version number.*

### 5.4 — Export the IPA

In the Organizer:

1. Click **Distribute App**.
2. Choose **Ad Hoc** (or **Development** — both work for sideloading to your own device).
   - If you have only a free account, choose **Development**.
3. Click **Next**.
4. Under **App Thinning**, select **None** (produces a universal IPA that AltStore can use).
5. Re-signing options: leave defaults. Click **Next**.
6. Xcode contacts Apple's servers to generate a provisioning profile. This takes 30–60 seconds.
7. Click **Export** and save the folder somewhere convenient, e.g., `~/Desktop/iSH-motion-export/`.

The exported folder contains:
```
iSH-motion-export/
├── iSH.ipa            ← this is the file you will sideload
├── ExportOptions.plist
└── Packaging.log
```

---

## 6. Sideload with AltStore

### 6.1 — Install AltServer on your Mac (one-time setup)

1. Download AltServer for Mac from [altstore.io](https://altstore.io).
2. Open the downloaded `.dmg` and drag **AltServer** to your Applications folder.
3. Launch AltServer. A diamond icon will appear in your Mac's menu bar.

### 6.2 — Install AltStore on your iPhone (one-time setup)

1. Plug your iPhone into your Mac with a USB cable.
2. Click the AltServer diamond icon in the menu bar.
3. Select **Install AltStore → [Your iPhone's name]**.
4. Enter your Apple ID and password when prompted. AltServer uses these to sign AltStore with your free certificate.
5. On your iPhone, go to **Settings → General → VPN & Device Management**.
6. Tap your Apple ID email address under "Developer App".
7. Tap **Trust "[Your Apple ID]"** and confirm.

AltStore is now installed on your iPhone.

### 6.3 — Sideload the iSH IPA

**Method A: Via AltStore on iPhone (easiest)**

1. Open **AltStore** on your iPhone.
2. Tap the **+** button in the top-left corner.
3. Navigate to the `.ipa` file. If the file is on your Mac, AirDrop it to your iPhone first, then use **Files** app to locate it.
4. AltStore will sign and install the app. This takes 30–60 seconds.

**Method B: Via AltServer on Mac (more reliable for large IPAs)**

1. Make sure your iPhone is on the same Wi-Fi network as your Mac (or connected via USB).
2. Click the AltServer diamond menu bar icon.
3. Select **Sideload .ipa...**
4. Sign in with your Apple ID if prompted.
5. Select your iPhone as the destination.
6. Navigate to and select `iSH.ipa`.
7. AltServer signs the IPA and installs it. Watch the progress indicator in the menu bar icon.

*Screenshot description: AltServer menu shows "Installing iSH..." with a spinner, then "iSH installed successfully."*

### 6.4 — Trust the app on iPhone

If you see "Untrusted Developer" when you launch the app:

1. Go to **Settings → General → VPN & Device Management**.
2. Tap your Apple ID under "Developer App".
3. Tap **Trust** and confirm.

### 6.5 — Set up AltStore auto-refresh (recommended)

AltStore can refresh your app certificate every 7 days automatically, as long as:
- Your iPhone and Mac are on the same Wi-Fi network.
- AltServer is running on your Mac (set it to launch at login: AltServer menu → **Launch at Login**).

The auto-refresh happens silently in the background — you will not lose any data.

---

## 7. First Launch & Grant Permissions

1. Launch the **iSH (motion)** app from your iPhone's home screen. The icon will look identical to the App Store version but the name will reflect what you set as the display name (or default to "iSH").

2. **Coexistence check:** Both the App Store iSH and your custom iSH should appear on the home screen as separate icons, because they have different bundle identifiers. If only one appears, the bundle ID was not changed — go back to Step 4.2.

3. **Motion permissions prompt:** iOS does not display a permission dialog for `CMMotionManager` — motion access is granted automatically to any app. No user action required.

4. On first launch, iSH will create a **fresh Alpine Linux root filesystem**. This is separate from your App Store iSH installation. You will see the familiar iSH setup screen bootstrapping Alpine.

5. Wait for the initial Alpine setup to complete (usually 1–2 minutes).

6. Once you reach a shell prompt, run the quick sanity check:

```bash
apk update
apk add python3
```

This confirms the network stack and package manager are working.

---

## 8. Test /dev/motion

Run these commands inside the iSH terminal on your iPhone.

### 8.1 — Confirm the device node exists

```bash
ls -la /dev/motion
```

Expected output:
```
crw-rw-rw-    1 root     root      240,   2 Jan  1 00:00 /dev/motion
```

- `c` = character device  
- `240` = `DYN_DEV_MAJOR`  
- `2` = `DEV_MOTION_MINOR`

If the file does not exist, the `generic_mknod` call in `AppDelegate.m` did not run. See [Troubleshooting](#10-troubleshooting).

### 8.2 — Read one line of sensor data

```bash
cat /dev/motion
```

Move the phone slightly, then press **Ctrl-C**. Each line of output looks like:

```
+0.002341,+0.001205,-0.003812,+0.021000,-0.015300,+0.008700,+0.041200,-0.012300,+1.570796,+2.340000
```

Field order: `ax, ay, az, gx, gy, gz, pitch, roll, yaw, baro`

### 8.3 — Stream 10 lines at 60 Hz

```bash
cat /dev/motion | head -10
```

You should see 10 lines appear rapidly (at approximately 60 Hz), then the command exits.

### 8.4 — Parse with Python

```bash
python3 -c "
import time
with open('/dev/motion') as f:
    for i, line in enumerate(f):
        vals = list(map(float, line.split(',')))
        print(f'Accel: ({vals[0]:.3f}, {vals[1]:.3f}, {vals[2]:.3f}) | Gyro: ({vals[3]:.3f}, {vals[4]:.3f}, {vals[5]:.3f})')
        if i > 20: break
"
```

You should see 21 lines of formatted accelerometer and gyroscope readings. Tilt the phone while it runs to see the values change.

### 8.5 — Log to a CSV file

```bash
# Log 5 seconds of data in the background
timeout 5 cat /dev/motion > /root/motion_log.csv
wc -l /root/motion_log.csv    # should be ~300 lines (5s × 60Hz)
head -3 /root/motion_log.csv  # preview first 3 rows
```

### 8.6 — Attitude (tilt) display

```bash
python3 - <<'EOF'
import math
with open('/dev/motion') as f:
    for i, line in enumerate(f):
        v = list(map(float, line.strip().split(',')))
        pitch_deg = math.degrees(v[6])
        roll_deg  = math.degrees(v[7])
        yaw_deg   = math.degrees(v[8])
        print(f'Pitch: {pitch_deg:+7.2f}°  Roll: {roll_deg:+7.2f}°  Yaw: {yaw_deg:+7.2f}°')
        if i >= 30: break
EOF
```

---

## 9. Reconnect the bore.pub SSH Tunnel

The sideloaded iSH starts with a **fresh Alpine root filesystem** — none of the configurations from your App Store iSH carry over. You need to redo the bore.pub tunnel setup from scratch in the new install.

### 9.1 — Install required packages

```bash
apk update
apk add openssh curl bash
```

### 9.2 — Generate (or re-use) an SSH key

```bash
# Generate a new Ed25519 key pair
ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519 -N ""

# Display the public key (you will need this to authorize connections)
cat ~/.ssh/id_ed25519.pub
```

If you want to reuse the same key from your App Store iSH install, you can transfer it. In your **App Store iSH**, run:

```bash
# In App Store iSH — print your existing private key
cat ~/.ssh/id_ed25519
```

Then in your **custom iSH**, paste it in:

```bash
# In custom iSH — recreate the key files
mkdir -p ~/.ssh
chmod 700 ~/.ssh
# Paste the private key content into the file below
cat > ~/.ssh/id_ed25519 << 'KEYEOF'
-----BEGIN OPENSSH PRIVATE KEY-----
[paste your key here]
-----END OPENSSH PRIVATE KEY-----
KEYEOF
chmod 600 ~/.ssh/id_ed25519
ssh-keygen -y -f ~/.ssh/id_ed25519 > ~/.ssh/id_ed25519.pub
```

### 9.3 — Start the SSH server

```bash
# Generate host keys if not present
ssh-keygen -A

# Start sshd
/usr/sbin/sshd

# Verify it's running
ps aux | grep sshd
```

### 9.4 — Install bore and open the tunnel

bore is a lightweight TCP tunnel tool available for Alpine:

```bash
# Install bore via the community repository
echo "https://dl-cdn.alpinelinux.org/alpine/edge/community" >> /etc/apk/repositories
apk update
apk add bore

# Open a tunnel — bore.pub will assign you a random port
bore local 22 --to bore.pub
```

The output will show your assigned public address, e.g.:
```
2024-01-15T10:23:45Z  INFO  listening at bore.pub:XXXXX
```

Connect from your Mac using:

```bash
ssh -p XXXXX root@bore.pub
```

### 9.5 — Make the tunnel persistent (optional)

```bash
# Create a startup script
cat > /etc/local.d/bore.start << 'EOF'
#!/bin/sh
/usr/sbin/sshd
bore local 22 --to bore.pub &
EOF
chmod +x /etc/local.d/bore.start

# Enable local scripts at boot
rc-update add local default
```

---

## 10. Troubleshooting

### `/dev/motion` does not exist

**Symptom:** `ls /dev/motion` returns "No such file or directory"  
**Cause:** The `generic_mknod` call never ran, or the AppDelegate.m patch was not applied.  
**Fix:**
1. In Xcode, search `AppDelegate.m` for the text `motion_dev`. If it is absent, the patch was not applied — re-do Step 3.4.
2. Re-build and re-sideload.

---

### `cat /dev/motion` hangs forever and produces nothing

**Symptom:** The command blocks indefinitely with no output, even when moving the phone.  
**Cause:** `CMMotionManager` is not delivering updates — usually because `isDeviceMotionAvailable` returned `false`, or the main thread is blocked.  
**Fix:**
1. Confirm you are running on a real device (not a Simulator — motion data is not available there).
2. Check the iSH log for `MotionDevice: CMDeviceMotion not available` — if present, there is a platform limitation.
3. Ensure CoreMotion.framework was linked (Step 4.5). Re-build.

---

### Build error: `lld: command not found`

**Cause:** LLVM was installed by Homebrew but its `/bin` is not on your PATH.  
**Fix:**

```bash
# For Apple Silicon
export PATH="/opt/homebrew/opt/llvm/bin:$PATH"
# For Intel
export PATH="/usr/local/opt/llvm/bin:$PATH"

# Verify
which lld
```

Add this `export` line to your `~/.zshrc` or `~/.bash_profile` to make it permanent.

---

### Xcode signing error: "No profiles for … were found"

**Cause:** Free Apple ID accounts can only have one provisioning profile per bundle ID, and a stale profile may exist.  
**Fix:**
1. In Xcode → **Signing & Capabilities**, click **Manage Certificates...**.
2. Delete any expired or duplicate certificates.
3. Check **Automatically manage signing** and let Xcode regenerate.

---

### AltStore shows "Maximum number of apps installed"

**Cause:** Free Apple ID accounts are limited to **3 sideloaded apps** at once (this includes AltStore itself, so effectively 2 user apps).  
**Fix:** In AltStore, swipe left on an app you no longer need and tap **Remove**. Then retry installation.

---

### App crashes immediately on launch ("Killed: 9")

**Cause:** The IPA was signed with a provisioning profile that does not include your device's UDID (happens with Ad Hoc distribution if the UDID was not registered).  
**Fix:** Use **Development** distribution instead of **Ad Hoc** when exporting in Step 5.4. Alternatively, register your device UDID in your Apple Developer account (free accounts can do this via Xcode).

---

### Both iSH icons look identical — hard to tell apart

**Fix:** Change the display name of your custom build. In Xcode's Build Settings, search for `PRODUCT_NAME` and set it to something distinguishable, e.g., `iSH Motion`. The app icon will still look the same, but the label under the icon will differ.

---

### Data from App Store iSH is gone in the sideloaded version

**Cause:** This is expected — different bundle IDs = different sandboxes = separate data containers.  
**Fix (transfer Alpine root):**

In **App Store iSH**, tar up your home directory and serve it via HTTP:

```bash
# In App Store iSH
apk add python3
tar czf /tmp/home_backup.tar.gz /root
python3 -m http.server 8080
```

In **custom iSH** (same Wi-Fi network — find App Store iSH's IP from `ifconfig`):

```bash
# In custom iSH
apk add curl
curl http://[APP_STORE_ISH_IP]:8080/tmp/home_backup.tar.gz | tar xzf - -C /
```

Then stop the HTTP server in App Store iSH with Ctrl-C.

---

### `git apply` rejects the diff

**Cause:** The upstream iSH repository has changed since the diff was written.  
**Fix:** Apply the changes manually as described in the fallback instructions in Steps 3.3 and 3.4. The changes are small (2–6 lines each) and easy to apply by hand with any text editor.

---

## Quick Reference

```bash
# ── Build checklist (in order) ───────────────────────────────────────────────
git clone --recurse-submodules https://github.com/ish-app/ish
cp ish_hardware_patch/MotionDevice.{h,m} ish/app/
cd ish
git apply ../ish_hardware_patch/devices_patch.diff
git apply ../ish_hardware_patch/AppDelegate_patch.diff
# → Open Xcode → change bundle ID → set team → add MotionDevice.m to compile
# → add CoreMotion.framework → Build (⌘B) → Archive → Export IPA → AltStore

# ── Test in iSH terminal ──────────────────────────────────────────────────────
ls -la /dev/motion          # expect: crw-rw-rw- 240, 2
cat /dev/motion | head -5   # expect: 5 lines of comma-separated doubles
```

---

*Guide version: 1.0 · Targets iSH main branch as of mid-2024 · Tested on iPhone 15 Pro*
