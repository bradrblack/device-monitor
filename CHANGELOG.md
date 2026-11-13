# Changelog

Notable changes to the firmware, newest first. Versions refer to
`FIRMWARE_VERSION` in `src/device-monitor.ino` (`src/vibration-monitor.ino`
before 2026-11-13r1).

## 2026-11-13r1

Rebuilt on the Sump Master 2000 firmware, cut down to on/off detection.

- **One image for every unit.** Device name, Wi-Fi, time zone, thresholds and
  connections are set at run time and kept on the board; the per-device
  PlatformIO environments (`pump`, `dryer`) are gone.
- **Wi-Fi setup portal** (WiFiManager, from the fan remote): opens on first boot,
  when the saved network can't be joined, on a double press of RESET, or from the
  web page. Sets the network, the device name and the admin password.
- **Web page** at `http://<name>.local/`: live state and vibration chart, guided
  calibration (measure idle, measure running, suggested thresholds), detection
  settings, device name and time zone, connections, firmware upload, log.
- **mDNS and OTA**: ArduinoOTA from PlatformIO and firmware upload from the web
  page, both with trial-and-rollback.
- **ADXL345 and ADXL346**, identified by device ID at boot, at address 0x53 or 0x1D.
- **Outputs**, each optional: InfluxDB (direct with a token, or via Telegraf),
  ntfy (any server; start/stop and daily report switchable), MQTT with Home
  Assistant discovery. **Adafruit IO is removed.**
- The accelerometer missing no longer reboots the board: detection pauses, it's
  retried every 30 s, and the web page and OTA keep working.
- New Telegraf listener config (`telegraf/devmon.conf`), extended Grafana
  dashboard and a "Device monitor silent" alert.
- Toolchain as Sump Master 2000: pioarduino 55.03.37, `min_spiffs` partitions
  (two 1.9 MB OTA slots; first flash after upgrading must be over USB).

## 2026-09-22r1

- Cap the Adafruit IO client's network timeout at 5 s. A stalled DNS lookup,
  TCP connect, or TLS handshake could chain across the library's default 3 s
  per-call timeout and exceed the 30 s task watchdog before failing — this
  happened at least once in the field (task watchdog reboot on the pump
  device).

## 2026-09-21r12

- Make serial logging non-blocking (`Serial.setTxTimeoutMs(0)`), so a USB
  host that's attached but not reading can no longer stall the main loop.
  Excess output is dropped instead of blocking.

## 2026-09-21r10

- Add a 30 s hardware task watchdog as a backstop for a hung main loop
  (stuck I2C, network, or USB call) that the existing in-loop watchdogs
  can't see. A hang now resets the board and is reported via ntfy as an
  unexpected reset.
- Add the `[env:dryer]` PlatformIO build environment.

## 2026-09-20r9

- Publish JSON events via MQTT (Adafruit IO) and add I2C boot diagnostics.
- Fix banner formatting.
- Pin the PlatformIO platform release to work around an upload bug in the
  unpinned "stable" zip.

## 2026-09-20r3

- Generalize from a single sump-pump monitor to a multi-device appliance
  monitor with JSON events.

## 2026-09-20r1

- Add source files, update README, add Telegraf/Grafana setup for an
  InfluxDB appliance timeline (non-firmware, tooling only).

## 2026-09-19r1

- Add reliability hardening (WiFi/Adafruit IO watchdogs, scheduled nightly
  reboot, boot-state correction) and ntfy.sh reboot notifications.

## Initial version

- Add the ESP32-C3 sump pump vibration monitor.
