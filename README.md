# iSH Hardware Sensor Patch — /dev/motion

## What This Adds

A new character device `/dev/motion` that streams iPhone/iPad sensor data into
iSH as a readable Linux device node — modeled exactly on the existing
`LocationDevice.m` pattern.

## Output Format

Each `read()` blocks until the next CMDeviceMotion update (~60 Hz), then returns one line:

```
ax,ay,az,gx,gy,gz,pitch,roll,yaw,baro\n
```

| Field | Type | Unit | Description |
|-------|------|------|-------------|
| ax/ay/az | double | g (gravity removed) | User acceleration X/Y/Z |
| gx/gy/gz | double | rad/s | Rotation rate X/Y/Z |
| pitch | double | radians | Attitude pitch |
| roll | double | radians | Attitude roll |
| yaw | double | radians | Attitude yaw |
| baro | double | metres | Relative altitude (0.0 if no barometer) |

Example output:
```
+0.002341,+0.001205,-0.003812,+0.021000,-0.015300,+0.008700,+0.041200,-0.012300,+1.570796,+2.340000
```

## Files Changed

| File | Change |
|------|--------|
| `app/MotionDevice.h` | New — device ops declaration |
| `app/MotionDevice.m` | New — full CMMotionManager + CMAltimeter implementation |
| `fs/devices.h` | Add `DEV_MOTION_MINOR 2` |
| `app/AppDelegate.m` | Register device + mknod at boot |

## Building

1. Clone iSH: `git clone https://github.com/ish-app/ish`
2. Copy `MotionDevice.h` and `MotionDevice.m` into `app/`
3. Apply `devices_patch.diff` and `AppDelegate_patch.diff`
4. Add `CoreMotion.framework` to Xcode target (Build Phases → Link Binary With Libraries)
5. Add `MotionDevice.m` to the Xcode target's "Compile Sources"
6. Build and sideload via AltStore / Sideloadly / dev cert

## Usage in iSH

```bash
# One-shot reading
cat /dev/motion

# Continuous stream at ~60 Hz (pipe into any tool)
cat /dev/motion | head -100

# Log to file
cat /dev/motion >> /root/motion_log.csv &

# Parse with Python
python3 - <<'PYEOF'
with open('/dev/motion') as f:
    for line in f:
        ax, ay, az, gx, gy, gz, pitch, roll, yaw, baro = map(float, line.split(','))
        print(f"Accel: ({ax:.3f}, {ay:.3f}, {az:.3f})")
PYEOF
```

## Xcode Build Requirements

Add to `app/App.xcconfig` or Build Settings:
```
OTHER_LDFLAGS = -framework CoreMotion
```

CoreMotion entitlement is automatically granted — no Info.plist key needed for
motion data (unlike Location which needs NSLocationAlwaysUsageDescription).
