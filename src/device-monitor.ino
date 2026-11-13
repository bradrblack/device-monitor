// Device Monitor: on/off status of anything that vibrates while it runs (sump
// pump, washer, dryer, AC unit...) from an ADXL345 or ADXL346 accelerometer on
// an ESP32-C3 SuperMini.
//
// The detection, reliability and reporting code is ported from Sump Master 2000
// (github.com/bradrblack/sump-master-2000); the Wi-Fi setup portal comes from the
// RF ceiling fan remote (github.com/bradrblack/rf-ceiling-fan-remote).
//
// Everything a unit needs is set at run time, so one firmware image serves every
// unit: Wi-Fi and the device name in the setup portal on first boot, and the
// rest (calibration, InfluxDB, ntfy, MQTT / Home Assistant) on the web page at
// http://<name>.local/. See README.md.

#include <Wire.h>
#include <WiFi.h>
#include <WiFiClientSecure.h>
#include <HTTPClient.h>
#include <Preferences.h>
#include <ArduinoOTA.h>
#include <ESPmDNS.h>
#include <WebServer.h>
#include <Update.h>
#include <PubSubClient.h>
#include <WiFiManager.h>
#include <time.h>
#include <sys/time.h>
#include <cstdarg>
#include <math.h>
#include <esp_system.h>
#include <esp_task_wdt.h>
#include <esp_ota_ops.h>
#include <esp32c3/rom/rtc.h>
#include <Adafruit_ADXL345_U.h>
// secrets.h is optional: everything in it can also be set at run time.
#if __has_include("secrets.h")
#include "secrets.h"
#endif
#include "web_page.h"

// Bump on each release -- format: YYYY-MM-DDrN.
#define FIRMWARE_VERSION "2026-11-13r1"

// ---- Build-time defaults (see platformio.ini) ---------------------------------
#ifndef OTA_PASSWORD
#error "OTA_PASSWORD is not set. Copy secrets.ini.example to secrets.ini (see platformio.ini)."
#endif

// Vibration thresholds (m/s^2 RMS): above ON_RMS_THRESHOLD = vibrating, below
// OFF_RMS_THRESHOLD = quiet, with the band in between as hysteresis. These are
// only the starting values: calibrate each unit on its web page.
#ifndef ON_RMS_THRESHOLD
#define ON_RMS_THRESHOLD 0.50f
#endif
#ifndef OFF_RMS_THRESHOLD
#define OFF_RMS_THRESHOLD 0.30f
#endif
// A run starts after RUN_CONFIRM_MS of continuous vibration and ends after
// STOP_CONFIRM_MS of continuous quiet.
#ifndef RUN_CONFIRM_MS
#define RUN_CONFIRM_MS 3000UL
#endif
#ifndef STOP_CONFIRM_MS
#define STOP_CONFIRM_MS 3000UL
#endif

// The SuperMini "v2" (external antenna) has a WS2812 NeoPixel on GPIO 8; older
// SuperMinis have a plain blue LED there, lit when the pin is LOW. Build with
// -DLED_NEOPIXEL=0 (env devmon-plain-led) for those.
#ifndef LED_NEOPIXEL
#define LED_NEOPIXEL 1
#endif

// Starting values for the connections; each can be changed at run time and is
// then kept on the board. An empty value turns that output off.
#ifndef WIFI_SSID
#define WIFI_SSID ""
#endif
#ifndef WIFI_PASS
#define WIFI_PASS ""
#endif
#ifndef DEVICE_NAME
#define DEVICE_NAME ""   // empty: "devmon-" plus the last 4 hex digits of the MAC
#endif
#ifndef INFLUX_URL
#define INFLUX_URL ""
#endif
#ifndef INFLUX_TOKEN
#define INFLUX_TOKEN ""
#endif
#ifndef NTFY_SERVER
#define NTFY_SERVER "https://ntfy.sh"
#endif
#ifndef NTFY_TOPIC
#define NTFY_TOPIC ""
#endif
#ifndef MQTT_HOST
#define MQTT_HOST ""
#endif
#ifndef MQTT_PORT
#define MQTT_PORT 1883
#endif
#ifndef MQTT_USER
#define MQTT_USER ""
#endif
#ifndef MQTT_PASS
#define MQTT_PASS ""
#endif
// POSIX TZ string, so DST is handled. Changeable on the web page.
#ifndef TZ_STRING
#define TZ_STRING "EST5EDT,M3.2.0,M11.1.0/2"
#endif

// NVS (flash) namespace for persisted state.
#define NVS_NS "devmon"

const char *BANNER =
// Starts with an empty line: the first characters printed after a reset can be
// lost while the USB serial port reconnects, which shifted the top line.
R"(
     _                                         _ _
  __| | _____   __  _ __ ___   ___  _ __  (_) |_ ___  _ __
 / _` |/ _ \ \ / / | '_ ` _ \ / _ \| '_ \ | | __/ _ \| '__|
| (_| |  __/\ V /  | | | | | | (_) | | | || | || (_) | |
 \__,_|\___| \_/   |_| |_| |_|\___/|_| |_||_|\__\___/|_|
)";

// ---- Pins (match the carrier PCB in hw/) --------------------------------------
const int SDA_PIN = 5;
const int SCL_PIN = 6;   // GPIO 2, 8 and 9 are boot strapping pins on the C3
const uint32_t I2C_CLOCK_HZ = 100000;  // 400 kHz was unreliable on the sm2k bench
const int LED_PIN = 8;
const uint8_t LED_BRIGHTNESS = 16;  // NeoPixel, 0-255; full brightness is blinding
const uint32_t LED_FLASH_HALF_PERIOD_MS = 500;
enum LedColor { LED_OFF_C, LED_GREEN, LED_YELLOW, LED_BLUE, LED_RED, LED_PURPLE, LED_WHITE };

// ---- Vibration detection ------------------------------------------------------
// Samples are high-passed against a slow per-axis baseline (removes gravity and
// mounting angle), then RMS'd over a short window.
const uint32_t SAMPLE_PERIOD_US   = 2500;   // 400 Hz, matches the accelerometer's data rate
const uint16_t SAMPLES_PER_WINDOW = 100;    // 250 ms windows
// High-pass cutoff ~ alpha * fs / 2pi = ~13 Hz: rejects footsteps / house rumble
// (<10 Hz) while passing motor vibration (~29-58 Hz for 1725/3450 RPM).
const float    BASELINE_ALPHA     = 0.2;

// Guided calibration: how long each capture (idle, running) lasts by default.
const uint32_t CAL_DEFAULT_MS = 30000;

// ---- Reporting ------------------------------------------------------------------
// A reading goes to InfluxDB every 10 minutes, on the wall-clock 10 minutes.
const uint32_t READING_PERIOD_S   = 600;
// Points waiting for InfluxDB, oldest first. 150 lines covers a day of
// readings plus events; if it fills, the oldest are dropped.
const int      IQ_SIZE            = 150;
const int      IQ_LINE_LEN        = 300;
const int      IQ_BATCH_LINES     = 20;
const uint32_t IQ_RETRY_MS        = 30000;
const uint32_t IQ_DOWN_ALERT_MS   = 1800000;  // alert after 30 min without a successful send

// ntfy priorities: 1 min, 2 low, 3 default, 4 high, 5 urgent.
const uint8_t PRIO_REPORT = 2;  // daily report: silent
const uint8_t PRIO_RUN    = 3;  // started / stopped
const uint8_t PRIO_INFO   = 3;  // reboots, updates, recoveries
const uint8_t PRIO_ALERT  = 4;  // sensor failures, rollbacks
const int      NTFY_QUEUE_SIZE    = 10;
const uint32_t NTFY_RETRY_MS      = 10000;

// ---- Reliability ------------------------------------------------------------------
// Older ESP32-C3 SuperMinis fail to join Wi-Fi at full TX power; 15 dBm is safe
// on every board. Drop to WIFI_POWER_8_5dBm if joins are flaky.
const wifi_power_t WIFI_TX_POWER = WIFI_POWER_15dBm;
const uint32_t WIFI_RETRY_MS           = 30000;   // reset the radio and retry this often
const uint32_t WIFI_DOWN_REBOOT_MS     = 120000;  // running: reboot if Wi-Fi down this long
// Setup portal: try saved Wi-Fi for this long, and keep the portal open this
// long with nobody using it before rebooting to try the saved network again.
const uint32_t WIFI_CONNECT_TIMEOUT_S  = 30;
const uint32_t PORTAL_TIMEOUT_S        = 300;
// Pressing RESET twice within this window (from power-up) opens the setup
// portal. The case has a pin hole over the RESET button.
const uint32_t DOUBLE_RESET_WINDOW_MS  = 5000;

// The accelerometer is polled for its fixed device ID; a wedged or unplugged
// I2C bus otherwise just produces a stream of zeros (looks like an idle device).
const uint32_t SENSOR_CHECK_INTERVAL_MS = 30000;
const int      SENSOR_FAIL_LIMIT        = 3;     // consecutive failed checks => treat as missing
const int      SAMPLE_FAIL_LIMIT        = 200;   // consecutive failed 400 Hz reads (0.5 s) => lost
const int      FLAT_WINDOW_LIMIT        = 40;    // consecutive windows (10 s) with rms exactly 0
const uint32_t ACCEL_RETRY_MS           = 30000;
// The ADXL345 and ADXL346 are register-compatible; only the device ID differs.
// The chip is identified at boot by reading it. Address 0x53 (SDO low, the
// GY-291/GY-346 module default) or 0x1D (SDO high).
const uint8_t  ADXL345_DEVICE_ID        = 0xE5;
const uint8_t  ADXL346_DEVICE_ID        = 0xE6;
const uint8_t  ACCEL_ADDRS[]            = {0x53, 0x1D};

// Scheduled reboot once a day at a fixed local hour, to guard against slow
// heap fragmentation. The daily report is pushed just before it.
#define REBOOT_HOUR 3
const char *NTP_SERVER = "pool.ntp.org";
#define REASON_DAILY_REBOOT "Daily scheduled reboot"
#define REASON_OTA_UPDATE   "OTA update"
#define REASON_USER         "Restarted from the web page"

// If the board was restarted while the last recorded event was a "start",
// correct it once the device has been observed for this long and is idle.
const uint32_t BOOT_SETTLE_MS = 15000;

// OTA: a freshly updated image runs as a trial. It's marked good once it has
// run for OTA_TRIAL_MIN_MS with Wi-Fi up and the accelerometer answering (if it
// was before the update); otherwise, after OTA_TRIAL_TIMEOUT_MS, it rolls back.
// A crash or reboot during the trial also rolls back (bootloader).
const uint32_t OTA_TRIAL_MIN_MS     = 180000;
const uint32_t OTA_TRIAL_TIMEOUT_MS = 600000;
const uint8_t  HEALTH_ACCEL = 0x01;

Adafruit_ADXL345_Unified accel = Adafruit_ADXL345_Unified(12345);

// ---- State ------------------------------------------------------------------------
float bx, by, bz;              // per-axis baseline
double sumSq = 0;
uint16_t sampleCount = 0;
uint32_t nextSampleUs = 0;

bool deviceRunning = false;
uint32_t aboveSince = 0;       // 0 = not currently above the start threshold
uint32_t belowSince = 0;       // 0 = not currently below the stop threshold
uint32_t runStartMs = 0;
uint32_t lastStatusMs = 0;
float lastRms = 0;
float maxRmsSinceStatus = 0;
int   loudWindowsSinceStatus = 0;
int lastRecordedState = -1;    // 1 start, 0 stop, -1 unknown; persisted in NVS

// Run statistics since boot (the daily reboot makes this roughly a day) and
// since the last 10-minute reading.
uint32_t cycleCount = 0;
uint32_t totalRunMs = 0;
uint32_t longestRunMs = 0;
uint32_t periodCycles = 0;
uint32_t periodRunMs = 0;
time_t   bootEpoch = 0;

// InfluxDB queue (ring buffer).
char     iq[IQ_SIZE][IQ_LINE_LEN];
int      iqHead = 0;
int      iqCount = 0;
uint32_t iqDropped = 0;
uint32_t lastIqFailMs = 0;     // 0 = last attempt succeeded
uint32_t lastIqOkMs = 0;
bool     iqAlerted = false;
uint32_t lastReadingSlot = UINT32_MAX;

// ntfy queue (ring buffer).
struct NtfyMsg {
  char title[64];
  char body[320];
  uint8_t priority;
  const char *tags;
};
NtfyMsg  ntfyQueue[NTFY_QUEUE_SIZE];
int      ntfyHead = 0;
int      ntfyCount = 0;
uint32_t lastNtfyFailMs = 0;

// Network, watchdogs, OTA.
uint32_t lastWifiAttempt = 0;
uint32_t wifiDownSince = 0;
int      lastRebootDay = -1;
int      sensorFails = 0;
int      accelReadFails = 0;
int      flatWindows = 0;
bool     accelOk = false;
uint8_t  accelAddr = ACCEL_ADDRS[0];
uint8_t  accelId = 0;          // device ID of the chip found (0 = never found)
uint32_t accelOkSinceMs = 0;
uint32_t lastAccelRetryMs = 0;
bool     accelAlerted = false;
uint32_t lastSensorCheck = 0;
bool     bootCorrectionDone = false;
bool     otaTrial = false;
uint8_t  otaRequiredHealth = HEALTH_ACCEL;
volatile bool otaDone = false;
bool     portalOpen = false;   // for the LED while the setup portal blocks
uint32_t restartAtMs = 0;      // a restart requested from the web page (0 = none)
const char *restartReason = REASON_USER;

// ---- Calibration settings -----------------------------------------------------------
// Changeable from the web page; kept in NVS (keys c_*).
struct Settings {
  float    onRms, offRms;              // m/s^2 RMS
  uint32_t runConfirmMs, stopConfirmMs;
};
const Settings DEFAULT_SETTINGS = { ON_RMS_THRESHOLD, OFF_RMS_THRESHOLD, RUN_CONFIRM_MS, STOP_CONFIRM_MS };
Settings cfg = DEFAULT_SETTINGS;

// ---- Device and connection settings ---------------------------------------------------
// Changeable at run time; kept in NVS (keys n_*). An empty InfluxDB URL, ntfy
// topic or MQTT host turns that output off. The admin password (for saving
// settings on the web page) starts as the OTA password.
struct NetConfig {
  char     name[25];         // device name = network name (<name>.local) = InfluxDB/MQTT id
  char     tz[48];
  char     influxUrl[160];
  char     influxToken[100];
  char     ntfyServer[64];
  char     ntfyTopic[65];
  bool     ntfyRun;          // push on start / stop
  bool     ntfyDaily;        // daily report push (doubles as a heartbeat)
  char     mqttHost[64];
  uint16_t mqttPort;
  char     mqttUser[33];
  char     mqttPass[65];
  char     adminPass[33];
};
NetConfig net;
const char *devName() { return net.name; }

// ---- MQTT / Home Assistant ------------------------------------------------------------
// State goes to devmon/<name>/state as one retained JSON message;
// devmon/<name>/status is "online"/"offline" (the broker publishes "offline"
// if the board vanishes). Home Assistant finds the entities through MQTT Discovery.
const uint32_t MQTT_RETRY_MS = 30000;
const uint32_t MQTT_STATE_MS = 30000;   // also sent at once on a start or stop
WiFiClient   mqttNet;
PubSubClient mqtt(mqttNet);
char     mqttBase[48];
uint32_t lastMqttAttemptMs = 0;
uint32_t lastMqttStateMs = 0;
bool     mqttDirty = true;
int      mqttDiscoveryIdx = -1;
bool     mqttFailLogged = false;
const char *mqttProblem();

struct HaEntity {
  const char *component;   // "sensor" or "binary_sensor"
  const char *id;          // also the key in the state JSON
  const char *name;
  const char *deviceClass; // "" = none
  const char *unit;
  const char *stateClass;
  bool        diagnostic;
};
const HaEntity HA_ENTITIES[] = {
  {"binary_sensor", "running",        "Running",               "running",         "",     "",                 false},
  {"sensor",        "vibration",      "Vibration",             "",                "m/s²", "measurement",      false},
  {"sensor",        "last_run_s",     "Last run",              "duration",        "s",    "",                 false},
  {"sensor",        "cycles",         "Runs since restart",    "",                "",     "total_increasing", false},
  {"binary_sensor", "sensor_problem", "Accelerometer",         "problem",         "",     "",                 true},
  {"sensor",        "rssi",           "Wi-Fi signal",          "signal_strength", "dBm",  "measurement",      true},
  {"sensor",        "uptime_s",       "Uptime",                "duration",        "s",    "",                 true},
  {"sensor",        "version",        "Firmware",              "",                "",     "",                 true},
};
const int HA_ENTITY_COUNT = sizeof(HA_ENTITIES) / sizeof(HA_ENTITIES[0]);

// ---- Vibration statistics (for calibration) -------------------------------------------
// Window RMS values, split by whether the device was idle or running. Windows
// seen while a start or stop is still being confirmed wait in vibPending and
// are counted once it's known which state they belonged to.
struct RmsAcc {
  double   sum = 0;
  uint32_t n = 0;
  float    mn = 0, mx = 0;
  void add(float v) { if (!n || v < mn) mn = v; if (!n || v > mx) mx = v; sum += v; n++; }
  void absorb(const RmsAcc &o) {
    if (!o.n) return;
    if (!n || o.mn < mn) mn = o.mn;
    if (!n || o.mx > mx) mx = o.mx;
    sum += o.sum; n += o.n;
  }
  float avg() const { return n ? (float)(sum / n) : 0; }
  void reset() { *this = RmsAcc(); }
};
RmsAcc   vibIdle, vibRun;       // since the last 10-minute reading
RmsAcc   vibIdleBoot;           // idle, since boot
RmsAcc   vibThisRun, vibLastRun;
RmsAcc   vibPending;
float    lastRunSeconds = 0;
uint32_t lastRunEndMs = 0;
float    statusMaxRms = 0;      // loudest window in the last full second

// Guided calibration captures, started from the web page: every window for a
// fixed time while the device is known to be idle, then while it's running.
enum CalPhase { CAL_NONE = 0, CAL_IDLE = 1, CAL_RUN = 2 };
CalPhase calPhase = CAL_NONE;
uint32_t calEndMs = 0;
RmsAcc   calIdle, calRun;

// ---- Log kept for the web page ----------------------------------------------------------
const int LOG_LINES    = 120;
const int LOG_LINE_LEN = 160;
char     logRing[LOG_LINES][LOG_LINE_LEN];
uint32_t logSeq = 0;
bool     logKeep = true;

WebServer web(80);
Preferences prefs;

// The Arduino core marks a new OTA image good as soon as it boots unless this
// returns true; the health check in checkOtaTrial() does it instead.
extern "C" bool verifyRollbackLater() { return true; }

// ==========================================
// Timestamped logging
// ==========================================
const char *logTimestamp() {
  static char buf[32];
  time_t now = time(nullptr);
  if (now > 100000) {
    struct tm timeinfo;
    localtime_r(&now, &timeinfo);
    strftime(buf, sizeof(buf), "%Y-%m-%d %H:%M:%S %Z", &timeinfo);
  } else {
    snprintf(buf, sizeof(buf), "+%lus", millis() / 1000);
  }
  return buf;
}

void logf(const char *fmt, ...) {
  char msg[256];
  va_list args;
  va_start(args, fmt);
  vsnprintf(msg, sizeof(msg), fmt, args);
  va_end(args);
  const char *ts = logTimestamp();
  Serial.printf("[%s] %s\r\n", ts, msg);
  if (logKeep) {
    snprintf(logRing[logSeq % LOG_LINES], LOG_LINE_LEN, "[%s] %s", ts, msg);
    logSeq++;
  }
}

void formatEventTime(char *buf, size_t len, uint32_t ageMs, const char *fmt) {
  buf[0] = 0;
  time_t now = time(nullptr);
  if (now < 100000) return;
  time_t t = now - (time_t)(ageMs / 1000);
  struct tm timeinfo;
  localtime_r(&t, &timeinfo);
  strftime(buf, len, fmt, &timeinfo);
}

// Wall-clock time ageMs ago in nanoseconds, or 0 if the clock hasn't synced.
uint64_t epochNs(uint32_t ageMs) {
  struct timeval tv;
  gettimeofday(&tv, nullptr);
  if (tv.tv_sec < 100000) return 0;
  int64_t ms = (int64_t)tv.tv_sec * 1000 + tv.tv_usec / 1000 - ageMs;
  return (uint64_t)ms * 1000000ULL;
}

const char *accelModel() {
  return accelId == ADXL346_DEVICE_ID ? "ADXL346" : accelId == ADXL345_DEVICE_ID ? "ADXL345" : "accelerometer";
}

// "1 h 12 min", "4 min 10 s" or "28.8 s".
String durationText(float seconds) {
  char buf[32];
  if (seconds >= 3600) snprintf(buf, sizeof(buf), "%d h %d min", (int)(seconds / 3600), ((int)seconds % 3600) / 60);
  else if (seconds >= 60) snprintf(buf, sizeof(buf), "%d min %d s", (int)(seconds / 60), (int)seconds % 60);
  else snprintf(buf, sizeof(buf), "%.1f s", seconds);
  return String(buf);
}

// ==========================================
// Notifications (ntfy)
// ==========================================
// Queued and sent from the main loop (one per 250 ms window), so a slow request
// never happens inside sensor handling, and a failed push is retried.
int sendNtfy(const NtfyMsg &m) {
  if (!net.ntfyTopic[0] || WiFi.status() != WL_CONNECTED) return -1;
  String url = String(net.ntfyServer) + "/" + net.ntfyTopic;
  WiFiClientSecure secure;
  WiFiClient plain;
  HTTPClient http;
  http.setConnectTimeout(5000);
  http.setTimeout(5000);
  bool ok;
  if (url.startsWith("https://")) {
    secure.setInsecure();
    secure.setTimeout(5);
    ok = http.begin(secure, url);
  } else {
    ok = http.begin(plain, url);
  }
  if (!ok) return -1;
  http.addHeader("Title", m.title);
  http.addHeader("Priority", String(m.priority));
  if (m.tags && m.tags[0]) http.addHeader("Tags", m.tags);
  int code = http.POST(String(m.body));
  http.end();
  logf("[ntfy] \"%s\" -> %d", m.title, code);
  return code;
}

// Queues a push titled "<device name><titleSuffix>". The body is printf-formatted.
// With no ntfy topic set it's only logged.
void notify(uint8_t priority, const char *tags, const char *titleSuffix, const char *fmt, ...) {
  NtfyMsg m;
  snprintf(m.title, sizeof(m.title), "%s%s", devName(), titleSuffix);
  va_list args;
  va_start(args, fmt);
  vsnprintf(m.body, sizeof(m.body), fmt, args);
  va_end(args);
  m.priority = priority;
  m.tags = tags;
  logf("[ntfy] %s: %s", m.title, m.body);
  if (!net.ntfyTopic[0]) return;
  if (ntfyCount == NTFY_QUEUE_SIZE) {
    logf("[ntfy] queue full, dropping oldest message");
    ntfyHead = (ntfyHead + 1) % NTFY_QUEUE_SIZE;
    ntfyCount--;
  }
  ntfyQueue[(ntfyHead + ntfyCount) % NTFY_QUEUE_SIZE] = m;
  ntfyCount++;
}

bool serviceNtfy(uint32_t now, bool force = false) {
  if (ntfyCount == 0 || WiFi.status() != WL_CONNECTED) return false;
  if (!force && lastNtfyFailMs && now - lastNtfyFailMs < NTFY_RETRY_MS) return false;
  int code = sendNtfy(ntfyQueue[ntfyHead]);
  bool sent = code >= 200 && code < 300;
  bool hopeless = code >= 400 && code < 500 && code != 429;
  if (sent || hopeless) {
    if (hopeless) logf("[ntfy] dropping message after HTTP %d", code);
    ntfyHead = (ntfyHead + 1) % NTFY_QUEUE_SIZE;
    ntfyCount--;
    lastNtfyFailMs = 0;
  } else {
    lastNtfyFailMs = now ? now : 1;
  }
  return sent;
}

// ==========================================
// Data to InfluxDB (line protocol over HTTP)
// ==========================================
// The URL is either Telegraf's http_listener_v2 (http://server:8186/devmon) or
// InfluxDB 2.x's own write API
// (http://server:8086/api/v2/write?org=home&bucket=devmon), in which case the
// token is sent as "Authorization: Token ...".
void addField(char *buf, size_t len, const char *fmt, ...) {
  size_t n = strlen(buf);
  if (n + 2 >= len) return;
  if (n) buf[n++] = ',';
  va_list args;
  va_start(args, fmt);
  vsnprintf(buf + n, len - n, fmt, args);
  va_end(args);
}

void escapeString(const char *s, char *out, size_t len) {
  size_t n = 0;
  for (; *s && n + 2 < len; s++) {
    if (*s == '"' || *s == '\\') out[n++] = '\\';
    out[n++] = *s;
  }
  out[n] = 0;
}

// Queues one point, timestamped ageMs ago. Device names are [a-z0-9-] only, so
// the tag needs no escaping. With no InfluxDB URL the point is only logged.
void influxPoint(const char *measurement, const char *fields, uint32_t ageMs = 0) {
  char line[IQ_LINE_LEN];
  uint64_t ns = epochNs(ageMs);
  int n = ns ? snprintf(line, sizeof(line), "%s,device=%s %s %llu", measurement, devName(), fields,
                        (unsigned long long)ns)
             : snprintf(line, sizeof(line), "%s,device=%s %s", measurement, devName(), fields);
  if (n >= (int)sizeof(line)) {
    logf("[influx] point too long, dropped: %s", measurement);
    return;
  }
  logf("[influx] %s: %s", net.influxUrl[0] ? "queued" : "off", line);
  if (!net.influxUrl[0]) return;
  if (iqCount == IQ_SIZE) {
    iqHead = (iqHead + 1) % IQ_SIZE;
    iqCount--;
    iqDropped++;
  }
  memcpy(iq[(iqHead + iqCount) % IQ_SIZE], line, n + 1);
  iqCount++;
}

bool serviceInflux(uint32_t now, bool force = false) {
  if (!net.influxUrl[0]) { iqCount = 0; return false; }
  if (iqCount == 0 || WiFi.status() != WL_CONNECTED) return false;
  if (!force && lastIqFailMs && now - lastIqFailMs < IQ_RETRY_MS) return false;

  int lines = iqCount < IQ_BATCH_LINES ? iqCount : IQ_BATCH_LINES;
  String body;
  body.reserve(lines * 110);
  for (int i = 0; i < lines; i++) {
    body += iq[(iqHead + i) % IQ_SIZE];
    body += '\n';
  }
  WiFiClient plain;
  WiFiClientSecure secure;
  HTTPClient http;
  http.setConnectTimeout(3000);
  http.setTimeout(5000);
  int code = -1;
  bool begun;
  if (strncmp(net.influxUrl, "https://", 8) == 0) {
    secure.setInsecure();
    secure.setTimeout(5);
    begun = http.begin(secure, net.influxUrl);
  } else {
    begun = http.begin(plain, net.influxUrl);
  }
  if (begun) {
    http.addHeader("Content-Type", "text/plain; charset=utf-8");
    if (net.influxToken[0]) http.addHeader("Authorization", String("Token ") + net.influxToken);
    code = http.POST(body);
    http.end();
  }
  bool sent = code >= 200 && code < 300;
  // A 4xx means the server rejected the data itself (or the token); retrying
  // would block the queue forever, so drop the batch. 401/403 mean a bad token.
  bool rejected = code >= 400 && code < 500;
  if (sent || rejected) {
    if (rejected) logf("[influx] server rejected %d point(s) (HTTP %d%s), dropped", lines, code,
                       code == 401 || code == 403 ? ", check the token" : "");
    iqHead = (iqHead + lines) % IQ_SIZE;
    iqCount -= lines;
    lastIqFailMs = 0;
    lastIqOkMs = now;
    if (iqAlerted) {
      iqAlerted = false;
      notify(PRIO_INFO, "white_check_mark", ": InfluxDB reachable again",
             "Sending data again. %lu point(s) were dropped while the queue was full.", (unsigned long)iqDropped);
    }
    iqDropped = 0;
  } else {
    logf("[influx] send failed (%d: %s), %d point(s) queued", code,
         code < 0 ? HTTPClient::errorToString(code).c_str() : "HTTP status", iqCount);
    lastIqFailMs = now ? now : 1;
  }
  return sent;
}

void checkInfluxWatchdog(uint32_t now) {
  if (iqCount == 0 || iqAlerted || now - lastIqOkMs < IQ_DOWN_ALERT_MS) return;
  iqAlerted = true;
  notify(PRIO_INFO, "warning", ": can't reach InfluxDB", "No data sent for %lu min; %d point(s) queued on the board.",
         (unsigned long)((now - lastIqOkMs) / 60000), iqCount);
}

void flushQueues(uint32_t timeoutMs) {
  uint32_t start = millis();
  while ((iqCount > 0 || ntfyCount > 0) && millis() - start < timeoutMs) {
    esp_task_wdt_reset();
    bool progress = false;
    if (iqCount > 0) progress |= serviceInflux(millis(), true);
    if (ntfyCount > 0) progress |= serviceNtfy(millis(), true);
    if (!progress) break;
  }
}

// ==========================================
// Reboot reporting
// ==========================================
String readRebootReason() {
  return prefs.isKey("last_reason") ? prefs.getString("last_reason", "") : String("");
}

bool expectedReason(const String &r) {
  return r == REASON_DAILY_REBOOT || r == REASON_OTA_UPDATE || r == REASON_USER;
}

void recordRebootReason(const char *reason) {
  prefs.begin(NVS_NS, false);
  prefs.putString("last_reason", reason);
  // Only count exception reboots, so "reboot #N" means something went wrong N times.
  if (!expectedReason(String(reason))) prefs.putUInt("reboot_count", prefs.getUInt("reboot_count", 0) + 1);
  prefs.end();
}

void restartWithReason(const char *reason) {
  logf("Restarting: %s", reason);
  recordRebootReason(reason);
  delay(100);
  ESP.restart();
}

// Detects a reboot that bypassed restartWithReason(): a crash, a hung loop
// tripping the hardware watchdog, a brownout. Must run before anything else
// in setup() can record a reason for this boot.
void checkUnexpectedReset() {
  prefs.begin(NVS_NS, false);
  String reason = readRebootReason();
  prefs.end();
  if (reason.length() > 0) return;

  esp_reset_reason_t r = esp_reset_reason();
  if (r == ESP_RST_POWERON || r == ESP_RST_EXT || r == ESP_RST_SW) return;
  RESET_REASON raw = rtc_get_reset_reason(0);
  if (raw == USB_UART_CHIP_RESET || raw == USB_JTAG_CHIP_RESET) return;

  const char *desc;
  switch (r) {
    case ESP_RST_PANIC:     desc = "crash/panic"; break;
    case ESP_RST_INT_WDT:   desc = "interrupt watchdog"; break;
    case ESP_RST_TASK_WDT:  desc = "task watchdog"; break;
    case ESP_RST_WDT:       desc = "other watchdog"; break;
    case ESP_RST_BROWNOUT:  desc = "brownout"; break;
    case ESP_RST_DEEPSLEEP: desc = "deep sleep wake"; break;
    default:                desc = "unknown"; break;
  }
  char buf[48];
  snprintf(buf, sizeof(buf), "Unexpected reset (%s)", desc);
  recordRebootReason(buf);
}

// Pushes the reason for the last reboot (if one was recorded) and records a
// boot point for the Grafana annotations.
void reportBoot() {
  prefs.begin(NVS_NS, false);
  String reason = readRebootReason();
  uint32_t count = prefs.getUInt("reboot_count", 0);
  if (reason.length() > 0) prefs.putString("last_reason", "");
  prefs.end();

  char esc[96], fields[200] = "";
  escapeString(reason.length() ? reason.c_str() : "power on or reset", esc, sizeof(esc));
  addField(fields, sizeof(fields), "version=\"%s\"", FIRMWARE_VERSION);
  addField(fields, sizeof(fields), "reason=\"%s\"", esc);
  addField(fields, sizeof(fields), "sensor=\"%s\"", accelId ? accelModel() : "none");
  influxPoint("appliance_boot", fields);

  if (reason.length() == 0 || expectedReason(reason)) return;
  notify(PRIO_INFO, "arrows_counterclockwise", " rebooted", "%s (reboot #%lu) at %s", reason.c_str(),
         (unsigned long)count, logTimestamp());
}

void saveLastRecordedState(int state) {
  prefs.begin(NVS_NS, false);
  prefs.putInt("last_state", state);
  prefs.end();
}

// ==========================================
// OTA updates (ArduinoOTA from PlatformIO, or a .bin uploaded on the web page)
// ==========================================
uint8_t currentHealth() { return accelOk ? HEALTH_ACCEL : 0; }

void checkOtaState() {
  esp_ota_img_states_t state;
  otaTrial = esp_ota_get_state_partition(esp_ota_get_running_partition(), &state) == ESP_OK &&
             state == ESP_OTA_IMG_PENDING_VERIFY;

  prefs.begin(NVS_NS, false);
  String trialVer = prefs.isKey("trial_ver") ? prefs.getString("trial_ver", "") : String("");
  String goodVer  = prefs.isKey("fw_ver") ? prefs.getString("fw_ver", "") : String("");
  otaRequiredHealth = prefs.getUChar("pre_health", HEALTH_ACCEL);
  if (otaTrial) {
    logf("[OTA] running new firmware as a trial (previous: %s)", goodVer.length() ? goodVer.c_str() : "unknown");
    prefs.putString("trial_ver", FIRMWARE_VERSION);
  } else {
    if (trialVer.length() > 0) {
      String why = prefs.isKey("trial_fail") ? prefs.getString("trial_fail", "")
                                             : String("it crashed or restarted before passing its health check");
      notify(PRIO_ALERT, "warning", ": update rolled back", "Firmware %s failed: %s. Back on %s.", trialVer.c_str(),
             why.c_str(), FIRMWARE_VERSION);
    }
    prefs.remove("trial_ver");
    prefs.remove("trial_fail");
    if (goodVer != FIRMWARE_VERSION) prefs.putString("fw_ver", FIRMWARE_VERSION);
  }
  prefs.end();
}

void failOtaTrial(const char *why) {
  logf("[OTA] trial failed (%s), rolling back", why);
  prefs.begin(NVS_NS, false);
  prefs.putString("trial_fail", why);
  prefs.end();
  flushQueues(5000);
  esp_ota_mark_app_invalid_rollback_and_reboot();
}

void checkOtaTrial(uint32_t now) {
  if (!otaTrial) return;
  bool wifiUp = WiFi.status() == WL_CONNECTED;
  uint8_t missing = otaRequiredHealth & ~currentHealth();
  if (now >= OTA_TRIAL_MIN_MS && wifiUp && missing == 0) {
    esp_ota_mark_app_valid_cancel_rollback();
    otaTrial = false;
    prefs.begin(NVS_NS, false);
    String prev = prefs.isKey("fw_ver") ? prefs.getString("fw_ver", "") : String("unknown");
    prefs.putString("fw_ver", FIRMWARE_VERSION);
    prefs.remove("trial_ver");
    prefs.remove("pre_health");
    prefs.end();
    logf("[OTA] trial passed, firmware %s marked good", FIRMWARE_VERSION);
    notify(PRIO_INFO, "arrow_up", " updated", "Firmware %s -> %s, passed its health check.", prev.c_str(),
           FIRMWARE_VERSION);
  } else if (now >= OTA_TRIAL_TIMEOUT_MS) {
    failOtaTrial(wifiUp ? "the accelerometer is not answering" : "Wi-Fi down");
  }
}

// The new image must bring back everything that works now.
void saveHealthBeforeUpdate() {
  prefs.begin(NVS_NS, false);
  prefs.putUChar("pre_health", currentHealth());
  prefs.end();
}

void restartAfterOta() {
  logf("[OTA] update received, restarting into it");
  flushQueues(5000);
  restartWithReason(REASON_OTA_UPDATE);
}

void setupOta() {
  // ArduinoOTA also starts mDNS, answering as <name>.local.
  ArduinoOTA.setHostname(devName());
  ArduinoOTA.setPassword(OTA_PASSWORD);
  ArduinoOTA.setRebootOnSuccess(false);
  ArduinoOTA.onStart([]() {
    logf("[OTA] update starting");
    saveHealthBeforeUpdate();
  });
  // The upload can take longer than the task watchdog's 30 s.
  ArduinoOTA.onProgress([](unsigned int, unsigned int) { esp_task_wdt_reset(); });
  ArduinoOTA.onEnd([]() { otaDone = true; });
  ArduinoOTA.onError([](ota_error_t err) { logf("[OTA] update failed (error %d)", (int)err); });
  ArduinoOTA.begin();
  logf("[OTA] ready: %s.local", devName());
}

// Accepts PlatformIO updates only while the device is idle (an upload stops
// sampling for ~15 s); retry once it stops.
void serviceOta() {
  if (!deviceRunning) ArduinoOTA.handle();
  if (otaDone) restartAfterOta();
}

// ==========================================
// Status LED
// ==========================================
// NeoPixel: green = idle, yellow = vibration seen but not (yet) a run,
// blue = running, flashing red = accelerometer missing, purple = setup portal
// open, flashing white = boot window in which a second RESET press opens the
// portal. Plain LED: off = idle, on = vibration seen, slow blink = running,
// fast blink = accelerometer missing, on = setup portal.

void ledWrite(LedColor c) {
#if LED_NEOPIXEL
  const uint8_t b = LED_BRIGHTNESS;
  switch (c) {
    case LED_GREEN:  rgbLedWrite(LED_PIN, 0, b, 0); break;
    case LED_YELLOW: rgbLedWrite(LED_PIN, b, b * 2 / 3, 0); break;
    case LED_BLUE:   rgbLedWrite(LED_PIN, 0, 0, b); break;
    case LED_RED:    rgbLedWrite(LED_PIN, b, 0, 0); break;
    case LED_PURPLE: rgbLedWrite(LED_PIN, b, 0, b); break;
    case LED_WHITE:  rgbLedWrite(LED_PIN, b, b, b); break;
    default:         rgbLedWrite(LED_PIN, 0, 0, 0); break;
  }
#else
  pinMode(LED_PIN, OUTPUT);
  digitalWrite(LED_PIN, c == LED_OFF_C || c == LED_GREEN ? HIGH : LOW);  // active low
#endif
}

void updateStatusLed() {
  static int last = -1;
  uint32_t ms = millis();
  bool slow = (ms / LED_FLASH_HALF_PERIOD_MS) % 2 == 0;
  bool fast = (ms / 125) % 2 == 0;
  LedColor c;
  if (portalOpen) c = LED_PURPLE;
  else if (!accelOk) c = LED_NEOPIXEL ? (slow ? LED_RED : LED_OFF_C) : (fast ? LED_RED : LED_OFF_C);
  else if (deviceRunning) c = LED_NEOPIXEL ? LED_BLUE : (slow ? LED_BLUE : LED_OFF_C);
  else if (lastRms >= cfg.offRms) c = LED_YELLOW;
  else c = LED_GREEN;
  if ((int)c == last) return;
  last = c;
  ledWrite(c);
}

// ==========================================
// Accelerometer
// ==========================================
// Reads X/Y/Z in one burst and reports whether the transfer worked (getEvent()
// gives no sign of a failed read). Scaled the same way the library does.
bool readSample(float &x, float &y, float &z) {
  Wire.beginTransmission(accelAddr);
  Wire.write((uint8_t)ADXL345_REG_DATAX0);
  if (Wire.endTransmission(false) != 0) return false;
  if (Wire.requestFrom(accelAddr, (uint8_t)6) != 6) return false;
  int16_t raw[3];
  for (int16_t &r : raw) {
    uint8_t lo = Wire.read();
    uint8_t hi = Wire.read();
    r = (int16_t)((hi << 8) | lo);
  }
  const float scale = ADXL345_MG2G_MULTIPLIER * SENSORS_GRAVITY_STANDARD;
  x = raw[0] * scale;
  y = raw[1] * scale;
  z = raw[2] * scale;
  return true;
}

// A reset can leave the sensor holding SDA low mid-byte, which no amount of
// rebooting the ESP32 clears. Clocking SCL up to 9 times lets it finish the
// byte and release the bus; then a STOP condition frees it.
void i2cBusRecover() {
  pinMode(SDA_PIN, INPUT_PULLUP);
  pinMode(SCL_PIN, OUTPUT);
  digitalWrite(SCL_PIN, HIGH);
  delayMicroseconds(10);
  for (int i = 0; i < 9 && digitalRead(SDA_PIN) == LOW; i++) {
    digitalWrite(SCL_PIN, LOW);  delayMicroseconds(10);
    digitalWrite(SCL_PIN, HIGH); delayMicroseconds(10);
  }
  pinMode(SDA_PIN, OUTPUT);
  digitalWrite(SDA_PIN, LOW);  delayMicroseconds(10);
  digitalWrite(SCL_PIN, HIGH); delayMicroseconds(10);
  digitalWrite(SDA_PIN, HIGH); delayMicroseconds(10);
}

void i2cScanLog() {
  logf("[I2C] idle levels: SDA=%d SCL=%d", digitalRead(SDA_PIN), digitalRead(SCL_PIN));
  int found = 0;
  for (uint8_t addr = 1; addr < 127; addr++) {
    Wire.beginTransmission(addr);
    if (Wire.endTransmission() == 0) {
      logf("[I2C] device ACKs at 0x%02X", addr);
      found++;
    }
  }
  if (!found) logf("[I2C] scan found no devices");
}

// Reads one register straight off the bus (the library's own reads go to the
// address it was begun with).
int readReg(uint8_t addr, uint8_t reg) {
  Wire.beginTransmission(addr);
  Wire.write(reg);
  if (Wire.endTransmission(false) != 0) return -1;
  if (Wire.requestFrom(addr, (uint8_t)1) != 1) return -1;
  return Wire.read();
}

bool isAccelId(int id) { return id == ADXL346_DEVICE_ID || id == ADXL345_DEVICE_ID; }

// Identifies the chip by its device ID (0xE5 = ADXL345, 0xE6 = ADXL346) at
// either I2C address. The Adafruit library's begin() only accepts 0xE5, so for
// an ADXL346 measurement mode is enabled here instead. The first transfer
// after the bus has been idle often fails, so retry a few times.
bool beginAccel() {
  for (int attempt = 1; attempt <= 5; attempt++) {
    for (uint8_t addr : ACCEL_ADDRS) {
      int id = readReg(addr, ADXL345_REG_DEVID);
      if (!isAccelId(id)) continue;
      accelAddr = addr;
      accelId = (uint8_t)id;
      bool ok = accel.begin(addr);
      if (!ok && id == ADXL346_DEVICE_ID) {
        accel.writeRegister(ADXL345_REG_POWER_CTL, 0x08);  // measure mode
        ok = true;
      }
      if (!ok) continue;
      logf("[I2C] %s detected at 0x%02X%s", accelModel(), addr,
           attempt > 1 ? (String(" on attempt ") + attempt).c_str() : "");
      return true;
    }
    delay(50);
  }
  return false;
}

bool startAccel() {
  if (!beginAccel()) return false;
  accel.setRange(ADXL345_RANGE_16_G);
  accel.setDataRate(ADXL345_DATARATE_400_HZ);
  if (!readSample(bx, by, bz)) return false;
  accelOk = true;
  accelReadFails = 0;
  flatWindows = 0;
  accelOkSinceMs = millis();
  sensorFails = 0;
  mqttDirty = true;
  return true;
}

// Carries on without the accelerometer: detection pauses (the run state is
// closed out, not guessed), one push says so, and it's retried every 30 s.
void accelLost(const char *why) {
  accelOk = false;
  mqttDirty = true;
  lastAccelRetryMs = millis();
  if (deviceRunning) {
    deviceRunning = false;
    influxPoint("appliance_state", "event=\"stop\",running=0i,note=\"sensor_lost\"");
    lastRecordedState = 0;
    saveLastRecordedState(0);
  }
  aboveSince = 0;
  belowSince = 0;
  vibPending.reset();
  vibThisRun.reset();
  logf("[I2C] accelerometer %s; detection paused, retrying every %lu s", why, (unsigned long)(ACCEL_RETRY_MS / 1000));
  if (accelAlerted) return;
  accelAlerted = true;
  notify(PRIO_ALERT, "warning", ": accelerometer not responding",
         "%s %s. On/off detection is paused; retrying every %lu s.", accelModel(), why,
         (unsigned long)(ACCEL_RETRY_MS / 1000));
}

void setupSensor() {
  // On a cold power-up the first bus start can leave the sensor unreachable;
  // stopping the bus, recovering it and starting it again has always worked.
  for (int attempt = 1; attempt <= 3; attempt++) {
    if (attempt > 1) {
      logf("[I2C] accelerometer not found, restarting the bus (try %d of 3)", attempt);
      Wire.end();
      delay(200);
    }
    i2cBusRecover();
    Wire.begin(SDA_PIN, SCL_PIN, I2C_CLOCK_HZ);
    if (startAccel()) return;
  }
  logf("[I2C] no ADXL345/ADXL346 at boot -- check wiring (SDA=%d SCL=%d)", SDA_PIN, SCL_PIN);
  i2cScanLog();
  accelLost("not detected at boot");
}

void checkSensorWatchdog(uint32_t now) {
  if (!accelOk) {
    if (now - lastAccelRetryMs < ACCEL_RETRY_MS) return;
    lastAccelRetryMs = now;
    Wire.end();
    i2cBusRecover();
    Wire.begin(SDA_PIN, SCL_PIN, I2C_CLOCK_HZ);
    if (startAccel() && accelAlerted) {
      accelAlerted = false;
      notify(PRIO_INFO, "white_check_mark", ": accelerometer OK", "%s answering again; detection resumed.", accelModel());
    }
    return;
  }
  if (now - lastSensorCheck < SENSOR_CHECK_INTERVAL_MS) return;
  lastSensorCheck = now;
  // Answering its ID isn't enough: it must also still be in measure mode
  // (POWER_CTL bit 3), or it reads a constant and the device looks idle forever.
  bool idOk = isAccelId(readReg(accelAddr, ADXL345_REG_DEVID));
  int power = idOk ? readReg(accelAddr, ADXL345_REG_POWER_CTL) : -1;
  if (idOk && power >= 0 && (power & 0x08)) {
    sensorFails = 0;
    return;
  }
  if (idOk) logf("[I2C] accelerometer answers but is not in measure mode");
  sensorFails++;
  logf("[I2C] accelerometer not responding (%d/%d)", sensorFails, SENSOR_FAIL_LIMIT);
  if (sensorFails >= SENSOR_FAIL_LIMIT) accelLost("stopped responding on I2C");
}

// ==========================================
// On/off detection
// ==========================================
void setRunState(bool running, uint32_t eventMs) {
  deviceRunning = running;
  uint32_t ageMs = millis() - eventMs;
  char at[32];
  formatEventTime(at, sizeof(at), ageMs, "%Y-%m-%d %H:%M:%S %Z");
  if (!at[0]) snprintf(at, sizeof(at), "uptime %lus", eventMs / 1000);
  char fields[160] = "";

  if (running) {
    runStartMs = eventMs;
    logf("%s STARTED", devName());
    addField(fields, sizeof(fields), "event=\"start\",running=1i");
    if (net.ntfyRun) notify(PRIO_RUN, "", " started", "Started at %s", at);
  } else {
    uint32_t dur = eventMs - runStartMs;
    float seconds = dur / 1000.0f;
    cycleCount++;
    totalRunMs += dur;
    periodCycles++;
    periodRunMs += dur;
    if (dur > longestRunMs) longestRunMs = dur;
    logf("%s STOPPED - ran %s (run %lu since restart)", devName(), durationText(seconds).c_str(),
         (unsigned long)cycleCount);
    addField(fields, sizeof(fields), "event=\"stop\",running=0i,seconds=%.1f", seconds);
    if (vibThisRun.n) {
      addField(fields, sizeof(fields), "rms_avg=%.3f,rms_min=%.3f", vibThisRun.avg(), vibThisRun.mn);
      vibLastRun = vibThisRun;
      lastRunSeconds = seconds;
      lastRunEndMs = millis();
      logf("[vib] run: average %.3f, lowest %.3f, highest %.3f m/s^2 RMS", vibThisRun.avg(), vibThisRun.mn,
           vibThisRun.mx);
    }
    vibThisRun.reset();
    if (net.ntfyRun) notify(PRIO_RUN, "", " stopped", "Stopped at %s (ran %s)", at, durationText(seconds).c_str());
  }
  influxPoint("appliance_state", fields, ageMs);
  mqttDirty = true;
  lastRecordedState = running ? 1 : 0;
  saveLastRecordedState(lastRecordedState);
}

void countIdle(const RmsAcc &a)    { vibIdle.absorb(a); vibIdleBoot.absorb(a); }
void countIdle(float rms)          { vibIdle.add(rms); vibIdleBoot.add(rms); }
void countRunning(const RmsAcc &a) { vibRun.absorb(a); vibThisRun.absorb(a); }
void countRunning(float rms)       { vibRun.add(rms); vibThisRun.add(rms); }

void serviceCalibration(float rms, uint32_t now) {
  if (calPhase == CAL_NONE) return;
  if (calPhase == CAL_IDLE) calIdle.add(rms);
  else calRun.add(rms);
  if ((int32_t)(now - calEndMs) < 0) return;
  const RmsAcc &a = calPhase == CAL_IDLE ? calIdle : calRun;
  logf("[cal] %s capture done: %lu windows, average %.3f, lowest %.3f, highest %.3f m/s^2 RMS",
       calPhase == CAL_IDLE ? "idle" : "running", (unsigned long)a.n, a.avg(), a.mn, a.mx);
  calPhase = CAL_NONE;
}

// Called once per 250 ms window with that window's RMS. Debounced: a run starts
// after runConfirmMs of continuous vibration above the start threshold and
// ends after stopConfirmMs of continuous quiet below the stop threshold.
void processWindow(float rms, uint32_t now) {
  lastRms = rms;
  if (rms > maxRmsSinceStatus) maxRmsSinceStatus = rms;
  if (rms >= cfg.offRms) loudWindowsSinceStatus++;
  if (!accelOk) return;
  serviceCalibration(rms, now);

  if (rms > cfg.onRms) {
    if (!aboveSince) aboveSince = now;
    belowSince = 0;
    if (deviceRunning) {
      countRunning(vibPending);   // a stop that didn't happen
      vibPending.reset();
      countRunning(rms);
    } else {
      vibPending.add(rms);
      if (now - aboveSince >= cfg.runConfirmMs) {
        countRunning(vibPending);
        vibPending.reset();
        setRunState(true, aboveSince);
      }
    }
  } else if (rms < cfg.offRms) {
    if (!belowSince) belowSince = now;
    aboveSince = 0;
    if (!deviceRunning) {
      countIdle(vibPending);      // a start that didn't happen (a bump, footsteps)
      vibPending.reset();
      countIdle(rms);
    } else {
      vibPending.add(rms);
      if (now - belowSince >= cfg.stopConfirmMs) {
        countIdle(vibPending);
        vibPending.reset();
        setRunState(false, belowSince);
      }
    }
  } else {
    // Hysteresis band: neither counts toward starting a run (footsteps are
    // impulsive, a motor is continuous) nor toward ending one.
    aboveSince = 0;
    belowSince = 0;
    if (deviceRunning) { countRunning(vibPending); countRunning(rms); }
    else               { countIdle(vibPending);    countIdle(rms); }
    vibPending.reset();
  }
}

// If we restarted while the last recorded event was a "start", record a stop
// (marked as a restart correction, with no run length) once the device has
// been observed idle for a while.
void checkBootStateCorrection(uint32_t now) {
  if (bootCorrectionDone || !accelOk || now - accelOkSinceMs < BOOT_SETTLE_MS) return;
  bootCorrectionDone = true;
  if (lastRecordedState == 1 && !deviceRunning) {
    logf("Last event was a start but the device is idle after a restart; correcting");
    influxPoint("appliance_state", "event=\"stop\",running=0i,note=\"restart\"");
    if (net.ntfyRun) notify(PRIO_RUN, "", " stopped", "Stopped while the board was restarting (%s); run time unknown",
                            logTimestamp());
    lastRecordedState = 0;
    saveLastRecordedState(0);
    mqttDirty = true;
  }
}

// ==========================================
// Periodic reading and daily report
// ==========================================
void checkPeriodicReading(uint32_t now) {
  time_t t = time(nullptr);
  uint32_t slot = t > 100000 ? (uint32_t)(t / READING_PERIOD_S) : now / (READING_PERIOD_S * 1000);
  if (slot == lastReadingSlot) return;
  bool first = lastReadingSlot == UINT32_MAX;
  lastReadingSlot = slot;
  if (first) return;

  char fields[IQ_LINE_LEN] = "";
  addField(fields, sizeof(fields), "running=%di,sensor_ok=%di", deviceRunning ? 1 : 0, accelOk ? 1 : 0);
  addField(fields, sizeof(fields), "cycles=%lui,run_s=%.1f", (unsigned long)periodCycles, periodRunMs / 1000.0f);
  addField(fields, sizeof(fields), "rssi=%di,heap=%lui", (int)WiFi.RSSI(), (unsigned long)ESP.getFreeHeap());
  if (vibIdle.n) addField(fields, sizeof(fields), "rms_idle_avg=%.3f,rms_idle_max=%.3f", vibIdle.avg(), vibIdle.mx);
  if (vibRun.n)  addField(fields, sizeof(fields), "rms_run_avg=%.3f,rms_run_min=%.3f", vibRun.avg(), vibRun.mn);
  addField(fields, sizeof(fields), "rms_on=%.3f,rms_off=%.3f", cfg.onRms, cfg.offRms);
  influxPoint("appliance_reading", fields);
  periodCycles = 0;
  periodRunMs = 0;
  vibIdle.reset();
  vibRun.reset();
}

void sendDailyReport() {
  if (!net.ntfyTopic[0] || !net.ntfyDaily) return;
  char since[32] = "boot";
  if (bootEpoch) {
    struct tm tm;
    localtime_r(&bootEpoch, &tm);
    strftime(since, sizeof(since), "%a %H:%M", &tm);
  }
  NtfyMsg m;
  snprintf(m.title, sizeof(m.title), "%s daily report", devName());
  snprintf(m.body, sizeof(m.body), "Now: %s\nSince %s: %lu run(s), %s total, longest %s\nFirmware %s, %s",
           !accelOk ? "unknown (accelerometer not responding)" : deviceRunning ? "running" : "off", since,
           (unsigned long)cycleCount, durationText(totalRunMs / 1000.0f).c_str(),
           durationText(longestRunMs / 1000.0f).c_str(), FIRMWARE_VERSION, accelModel());
  m.priority = PRIO_REPORT;
  m.tags = "clipboard";
  logf("[ntfy] daily report:\n%s", m.body);
  for (int attempt = 0; attempt < 3; attempt++) {
    esp_task_wdt_reset();
    int code = sendNtfy(m);
    if (code >= 200 && code < 300) return;
    delay(2000);
  }
  logf("[ntfy] daily report could not be sent");
}

// Reboots once per day at REBOOT_HOUR local time, sending the daily report
// first. Held off while the device runs, a push is waiting or an OTA trial runs.
void checkDailyReboot() {
  time_t now = time(nullptr);
  if (now < 100000) return;
  struct tm timeinfo;
  localtime_r(&now, &timeinfo);
  if (timeinfo.tm_hour != REBOOT_HOUR || timeinfo.tm_mday == lastRebootDay) return;
  if (deviceRunning || ntfyCount > 0 || otaTrial || calPhase != CAL_NONE) return;
  lastRebootDay = timeinfo.tm_mday;
  // Persisted, so the reboot this triggers doesn't fire again in the same hour.
  prefs.begin(NVS_NS, false);
  prefs.putInt("last_reboot_day", lastRebootDay);
  prefs.end();
  sendDailyReport();
  flushQueues(5000);
  restartWithReason(REASON_DAILY_REBOOT);
}

// ==========================================
// Device and connection settings (NVS)
// ==========================================
// True if every character is printable ASCII other than space, quotes and
// backslash (so values can go into JSON, URLs and headers as they are).
bool plainText(const char *s) {
  for (; *s; s++) if (*s <= ' ' || *s > '~' || *s == '"' || *s == '\\' || *s == '\'') return false;
  return true;
}

// Device names become the network name (<name>.local), the InfluxDB tag and
// part of MQTT topics: 1-24 characters, a-z, 0-9 and "-", not at either end.
bool validName(const char *s) {
  size_t n = strlen(s);
  if (n < 1 || n > 24 || s[0] == '-' || s[n - 1] == '-') return false;
  for (; *s; s++) if (!((*s >= 'a' && *s <= 'z') || (*s >= '0' && *s <= '9') || *s == '-')) return false;
  return true;
}

String lowerTrim(String s) {
  s.trim();
  s.toLowerCase();
  return s;
}

void defaultName(char *out, size_t len) {
  uint8_t mac[6];
  WiFi.macAddress(mac);
  snprintf(out, len, "devmon-%02x%02x", mac[4], mac[5]);
}

void loadNetString(const char *key, char *out, size_t len, const char *fallback) {
  if (prefs.isKey(key)) prefs.getString(key, out, len);
  else snprintf(out, len, "%s", fallback);
}

void loadNetConfig() {
  prefs.begin(NVS_NS, false);
  loadNetString("n_name", net.name, sizeof(net.name), DEVICE_NAME);
  loadNetString("n_tz", net.tz, sizeof(net.tz), TZ_STRING);
  loadNetString("n_iurl", net.influxUrl, sizeof(net.influxUrl), INFLUX_URL);
  loadNetString("n_itok", net.influxToken, sizeof(net.influxToken), INFLUX_TOKEN);
  loadNetString("n_nsrv", net.ntfyServer, sizeof(net.ntfyServer), NTFY_SERVER);
  loadNetString("n_ntfy", net.ntfyTopic, sizeof(net.ntfyTopic), NTFY_TOPIC);
  loadNetString("n_mhost", net.mqttHost, sizeof(net.mqttHost), MQTT_HOST);
  loadNetString("n_muser", net.mqttUser, sizeof(net.mqttUser), MQTT_USER);
  loadNetString("n_mpass", net.mqttPass, sizeof(net.mqttPass), MQTT_PASS);
  loadNetString("n_admin", net.adminPass, sizeof(net.adminPass), OTA_PASSWORD);
  net.mqttPort = prefs.getUShort("n_mport", MQTT_PORT);
  net.ntfyRun = prefs.getBool("n_nrun", true);
  net.ntfyDaily = prefs.getBool("n_nday", true);
  prefs.end();
  if (!validName(net.name)) defaultName(net.name, sizeof(net.name));
  if (!net.tz[0]) snprintf(net.tz, sizeof(net.tz), "%s", TZ_STRING);
}

void saveNetConfig() {
  prefs.begin(NVS_NS, false);
  prefs.putString("n_name", net.name);
  prefs.putString("n_tz", net.tz);
  prefs.putString("n_iurl", net.influxUrl);
  prefs.putString("n_itok", net.influxToken);
  prefs.putString("n_nsrv", net.ntfyServer);
  prefs.putString("n_ntfy", net.ntfyTopic);
  prefs.putString("n_mhost", net.mqttHost);
  prefs.putString("n_muser", net.mqttUser);
  prefs.putString("n_mpass", net.mqttPass);
  prefs.putString("n_admin", net.adminPass);
  prefs.putUShort("n_mport", net.mqttPort);
  prefs.putBool("n_nrun", net.ntfyRun);
  prefs.putBool("n_nday", net.ntfyDaily);
  prefs.end();
}

void logNetConfig(const char *what) {
  logf("[net] %s: name %s; InfluxDB %s%s; ntfy %s; MQTT %s%s", what, net.name,
       net.influxUrl[0] ? net.influxUrl : "off", net.influxToken[0] ? " (with token)" : "",
       net.ntfyTopic[0] ? net.ntfyServer : "off", net.mqttHost[0] ? net.mqttHost : "off",
       net.mqttUser[0] ? " (with login)" : "");
}

// ==========================================
// Calibration settings (NVS)
// ==========================================
const char *settingsProblem(const Settings &c) {
  if (!(c.onRms >= 0.05f && c.onRms <= 20.0f)) return "The start threshold must be between 0.05 and 20 m/s^2.";
  if (!(c.offRms >= 0.02f && c.offRms <= c.onRms * 0.95f))
    return "The stop threshold must be at least 0.02 and clearly below the start threshold.";
  if (c.runConfirmMs < 500 || c.runConfirmMs > 600000) return "The start time must be between 0.5 and 600 seconds.";
  if (c.stopConfirmMs < 500 || c.stopConfirmMs > 3600000) return "The stop time must be between 0.5 and 3600 seconds.";
  return nullptr;
}

void logSettings(const char *what) {
  logf("[cfg] %s: start %.2f / stop %.2f m/s^2, confirm %.1f / %.1f s", what, cfg.onRms, cfg.offRms,
       cfg.runConfirmMs / 1000.0f, cfg.stopConfirmMs / 1000.0f);
}

void loadSettings() {
  Settings c = DEFAULT_SETTINGS;
  prefs.begin(NVS_NS, false);
  bool any = prefs.isKey("c_on");
  if (any) {
    c.onRms         = prefs.getFloat("c_on", c.onRms);
    c.offRms        = prefs.getFloat("c_off", c.offRms);
    c.runConfirmMs  = prefs.getULong("c_runms", c.runConfirmMs);
    c.stopConfirmMs = prefs.getULong("c_stopms", c.stopConfirmMs);
  }
  prefs.end();
  const char *problem = settingsProblem(c);
  if (problem) {
    logf("[cfg] saved settings rejected (%s); using the firmware defaults", problem);
    c = DEFAULT_SETTINGS;
  }
  cfg = c;
  logSettings(any && !problem ? "saved settings" : "firmware defaults");
}

void applySettings(const Settings &c, bool useDefaults) {
  cfg = c;
  prefs.begin(NVS_NS, false);
  if (useDefaults) {
    for (const char *k : {"c_on", "c_off", "c_runms", "c_stopms"}) prefs.remove(k);
  } else {
    prefs.putFloat("c_on", c.onRms);
    prefs.putFloat("c_off", c.offRms);
    prefs.putULong("c_runms", c.runConfirmMs);
    prefs.putULong("c_stopms", c.stopConfirmMs);
  }
  prefs.end();
  aboveSince = 0;   // the debounce timers were measured against the old thresholds
  belowSince = 0;
  logSettings(useDefaults ? "reset to firmware defaults" : "settings changed");
  char fields[160] = "";
  addField(fields, sizeof(fields), "rms_on=%.3f,rms_off=%.3f,run_confirm_s=%.1f,stop_confirm_s=%.1f", cfg.onRms,
           cfg.offRms, cfg.runConfirmMs / 1000.0f, cfg.stopConfirmMs / 1000.0f);
  influxPoint("appliance_config", fields);
}

// ==========================================
// Wi-Fi: setup portal (WiFiManager), connection and watchdog
// ==========================================
// The portal opens on first boot (no saved network), when the saved network
// can't be joined, after a double press of RESET, or from the web page. It's
// an open access point named "DeviceMonitor-XXXX": join it from a phone, pick
// the Wi-Fi network and set the device name.
bool portalSaved = false;
void onPortalSave() { portalSaved = true; }

void apName(char *out, size_t len) {
  uint8_t mac[6];
  WiFi.macAddress(mac);
  snprintf(out, len, "DeviceMonitor-%02X%02X", mac[4], mac[5]);
}

// NVS flag "drd" is set at power-up and cleared DOUBLE_RESET_WINDOW_MS later;
// finding it already set means RESET was pressed again inside the window.
// NVS rather than RTC memory, because the C3's RESET pin resets everything.
bool checkDoubleReset() {
  prefs.begin(NVS_NS, false);
  bool second = prefs.getBool("drd", false);
  bool requested = prefs.getBool("portal", false);
  if (second) prefs.putBool("drd", false);
  else prefs.putBool("drd", true);
  if (requested) prefs.remove("portal");
  prefs.end();
  if (second) {
    logf("[WiFi] RESET pressed twice: opening the setup portal");
    return true;
  }
  if (requested) logf("[WiFi] setup portal requested from the web page");
  return requested;
}

// Waits out the rest of the double-reset window (flashing the LED white so a
// second press is easy to time), then clears the flag.
void finishDoubleResetWindow() {
  while (millis() < DOUBLE_RESET_WINDOW_MS) {
    ledWrite((millis() / 150) % 2 ? LED_WHITE : LED_OFF_C);
    delay(10);
  }
  prefs.begin(NVS_NS, false);
  prefs.putBool("drd", false);
  prefs.end();
}

// The TX power cap is lost whenever the Wi-Fi driver restarts, and WiFiManager
// restarts it (mode changes, its own connect attempts, the portal's AP+STA mode)
// after setupWiFi() has set it. Older SuperMinis then fail to join at full power.
// So reapply the cap every time the station or the access point starts.
// Also remember why the last join attempt failed, for the log.
volatile uint8_t lastDisconnectReason = 0;

void onWiFiEvent(arduino_event_id_t event, arduino_event_info_t info) {
  switch (event) {
    case ARDUINO_EVENT_WIFI_STA_START:
    case ARDUINO_EVENT_WIFI_AP_START:
      WiFi.setTxPower(WIFI_TX_POWER);
      Serial.printf("[WiFi] %s started, TX power set to %d (x0.25 dBm)\n",
                    event == ARDUINO_EVENT_WIFI_AP_START ? "AP" : "station", (int)WiFi.getTxPower());
      break;
    case ARDUINO_EVENT_WIFI_STA_DISCONNECTED:
      lastDisconnectReason = info.wifi_sta_disconnected.reason;
      // Printed straight away (WiFiManager blocks for 30 s while it retries)
      Serial.printf("[WiFi] join failed: reason %u (%s), RSSI %d\n", lastDisconnectReason,
                    WiFi.disconnectReasonName((wifi_err_reason_t)lastDisconnectReason),
                    (int)info.wifi_sta_disconnected.rssi);
      break;
    default:
      break;
  }
}

void setupWiFi(bool forcePortal) {
  char ap[32];
  apName(ap, sizeof(ap));
  static bool eventsHooked = false;
  if (!eventsHooked) {
    WiFi.onEvent(onWiFiEvent);
    eventsHooked = true;
  }

  // A clean radio before WiFiManager decides between joining and the portal:
  // without it a phone joining the portal can fail DHCP (seen on the fan remote).
  WiFi.mode(WIFI_OFF);
  delay(200);
  WiFi.mode(WIFI_STA);
  WiFi.setTxPower(WIFI_TX_POWER);
  WiFi.setHostname(net.name);

  // Seed the network from secrets.h on a board that has none saved yet.
  WiFiManager wm;
  if (!wm.getWiFiIsSaved() && WIFI_SSID[0]) {
    logf("[WiFi] no saved network; using \"%s\" from secrets.h", WIFI_SSID);
    WiFi.begin(WIFI_SSID, WIFI_PASS);
  }

  char adminHint[] = "";
  WiFiManagerParameter pName("devname", "Device name (lowercase letters, digits and -; it becomes &lt;name&gt;.local)",
                             net.name, sizeof(net.name) - 1);
  WiFiManagerParameter pAdmin("admin", "New admin password for the web page (8+ characters; empty keeps the current one)",
                              adminHint, sizeof(net.adminPass) - 1, "type=\"password\"");
  wm.setTitle("Device Monitor");
  wm.setHostname(net.name);
  wm.setSaveConfigCallback(onPortalSave);
  wm.setSaveParamsCallback(onPortalSave);
  wm.addParameter(&pName);
  wm.addParameter(&pAdmin);
  // No firmware upload from the open portal: updates need the admin password.
  std::vector<const char *> menu = {"wifi", "info", "sep", "restart", "exit"};
  wm.setMenu(menu);
  wm.setConnectTimeout(WIFI_CONNECT_TIMEOUT_S);
  wm.setConfigPortalTimeout(PORTAL_TIMEOUT_S);
  wm.setAPCallback([](WiFiManager *) {
    portalOpen = true;
    ledWrite(LED_PURPLE);
    logf("[WiFi] setup portal open: join the Wi-Fi network shown below and browse to http://192.168.4.1/");
  });

  logf("[WiFi] connecting (or opening the \"%s\" setup portal)", ap);
  bool ok = forcePortal ? wm.startConfigPortal(ap) : wm.autoConnect(ap);
  portalOpen = false;
  if (lastDisconnectReason) {
    // 15 = wrong password, 201 = network not found, 2/202/204 = auth or handshake trouble
    logf("[WiFi] last failed join: reason %u (%s), TX power %d (x0.25 dBm)", lastDisconnectReason,
         WiFi.disconnectReasonName((wifi_err_reason_t)lastDisconnectReason), (int)WiFi.getTxPower());
  }

  if (portalSaved) {
    String name = lowerTrim(pName.getValue());
    String admin = String(pAdmin.getValue());
    bool changed = false;
    if (name.length() && name != net.name) {
      if (validName(name.c_str())) {
        snprintf(net.name, sizeof(net.name), "%s", name.c_str());
        changed = true;
      } else {
        logf("[WiFi] device name \"%s\" ignored (use a-z, 0-9 and -, up to 24)", name.c_str());
      }
    }
    if (admin.length() >= 8 && admin.length() < sizeof(net.adminPass) && plainText(admin.c_str())) {
      snprintf(net.adminPass, sizeof(net.adminPass), "%s", admin.c_str());
      changed = true;
    } else if (admin.length()) {
      logf("[WiFi] admin password ignored (8-32 characters, no spaces, quotes or backslash)");
    }
    if (changed) {
      saveNetConfig();
      logNetConfig("set in the setup portal");
    }
    // The new name only reaches DHCP and mDNS on a fresh start.
    if (ok && changed) restartWithReason(REASON_USER);
  }

  if (!ok) {
    // Timed out with nobody configuring it: restart and try the saved network again.
    restartWithReason("Wi-Fi setup portal timed out");
  }
  WiFi.setSleep(false);
  WiFi.setAutoReconnect(true);
  logf("[WiFi] connected to \"%s\", IP address %s", WiFi.SSID().c_str(), WiFi.localIP().toString().c_str());
}

void setupTime() {
  configTzTime(net.tz, NTP_SERVER);
  logf("[NTP] syncing time");
  time_t now = time(nullptr);
  uint32_t start = millis();
  while (now < 100000 && millis() - start < 10000) {
    delay(250);
    now = time(nullptr);
  }
  logf(now < 100000 ? "[NTP] failed to sync (will keep retrying in the background)" : "[NTP] synced");
}

void checkBootEpoch() {
  if (bootEpoch) return;
  time_t now = time(nullptr);
  if (now > 100000) bootEpoch = now - millis() / 1000;
}

void serviceNetwork(uint32_t now) {
  if (WiFi.status() != WL_CONNECTED) {
    if (now - lastWifiAttempt >= WIFI_RETRY_MS) {
      lastWifiAttempt = now;
      // A connect attempt can get stuck; fully reset the radio first. The
      // saved network (from the portal) is reused.
      WiFi.disconnect(true);
      delay(200);
      WiFi.mode(WIFI_STA);
      WiFi.setTxPower(WIFI_TX_POWER);
      WiFi.setHostname(net.name);
      WiFi.begin();
    }
    return;
  }
  serviceInflux(now);
  serviceNtfy(now);
}

void checkWiFiWatchdog() {
  if (WiFi.status() != WL_CONNECTED) {
    if (wifiDownSince == 0) wifiDownSince = millis();
    else if (millis() - wifiDownSince > WIFI_DOWN_REBOOT_MS) restartWithReason("WiFi down watchdog");
  } else {
    wifiDownSince = 0;
  }
}

// ==========================================
// MQTT / Home Assistant
// ==========================================
const char *mqttProblem() {
  switch (mqtt.state()) {
    case MQTT_CONNECT_BAD_CREDENTIALS:
    case MQTT_CONNECT_UNAUTHORIZED:    return "the broker refused the user name or password";
    case MQTT_CONNECT_FAILED:          return "no answer from the broker";
    case MQTT_CONNECTION_TIMEOUT:      return "the broker stopped answering";
    case MQTT_CONNECTION_LOST:         return "the connection dropped";
    case MQTT_CONNECT_BAD_CLIENT_ID:   return "the broker refused the client ID";
    case MQTT_CONNECT_UNAVAILABLE:     return "the broker is not accepting connections";
    default:                           return "not connected";
  }
}

void setupMqtt() {
  snprintf(mqttBase, sizeof(mqttBase), "devmon/%s", devName());
  mqtt.setBufferSize(1024);
  mqtt.setKeepAlive(30);
  mqtt.setSocketTimeout(3);
  mqttNet.setConnectionTimeout(2000);
}

void haTopic(char *out, size_t len, const HaEntity &e, const char *name) {
  snprintf(out, len, "homeassistant/%s/devmon_%s/%s/config", e.component, name, e.id);
}

bool publishHaDiscovery(const HaEntity &e) {
  char topic[96], msg[760];
  haTopic(topic, sizeof(topic), e, devName());
  int n = snprintf(msg, sizeof(msg),
                   "{\"name\":\"%s\",\"uniq_id\":\"devmon_%s_%s\",\"stat_t\":\"%s/state\",\"avty_t\":\"%s/status\","
                   "\"val_tpl\":\"{{ value_json.%s | default('None') }}\"",
                   e.name, devName(), e.id, mqttBase, mqttBase, e.id);
  if (e.deviceClass[0]) n += snprintf(msg + n, sizeof(msg) - n, ",\"dev_cla\":\"%s\"", e.deviceClass);
  if (e.unit[0])        n += snprintf(msg + n, sizeof(msg) - n, ",\"unit_of_meas\":\"%s\"", e.unit);
  if (e.stateClass[0])  n += snprintf(msg + n, sizeof(msg) - n, ",\"stat_cla\":\"%s\"", e.stateClass);
  if (e.diagnostic)     n += snprintf(msg + n, sizeof(msg) - n, ",\"ent_cat\":\"diagnostic\"");
  n += snprintf(msg + n, sizeof(msg) - n,
                ",\"dev\":{\"ids\":[\"devmon_%s\"],\"name\":\"%s\",\"mf\":\"bradrblack\","
                "\"mdl\":\"Device Monitor (%s)\",\"sw\":\"%s\",\"cu\":\"http://%s.local/\"}}",
                devName(), devName(), accelModel(), FIRMWARE_VERSION, devName());
  if (n >= (int)sizeof(msg)) return false;
  return mqtt.publish(topic, msg, true);
}

// On a rename: remove the old name's retained discovery messages and state,
// so Home Assistant doesn't keep a dead copy of the device.
void mqttForgetName(const char *oldName) {
  if (!mqtt.connected()) return;
  char topic[96];
  for (const HaEntity &e : HA_ENTITIES) {
    haTopic(topic, sizeof(topic), e, oldName);
    mqtt.publish(topic, "", true);
  }
  snprintf(topic, sizeof(topic), "devmon/%s/state", oldName);
  mqtt.publish(topic, "", true);
  snprintf(topic, sizeof(topic), "devmon/%s/status", oldName);
  mqtt.publish(topic, "", true);
  mqtt.loop();
  mqtt.disconnect();  // a clean disconnect, so the broker doesn't publish the old will
}

void jsonAdd(char *buf, size_t len, const char *fmt, ...) {
  size_t n = strlen(buf);
  if (n + 1 >= len) return;
  va_list args;
  va_start(args, fmt);
  vsnprintf(buf + n, len - n, fmt, args);
  va_end(args);
}

bool publishMqttState(uint32_t now) {
  char topic[64], msg[400] = "{";
  snprintf(topic, sizeof(topic), "%s/state", mqttBase);
  jsonAdd(msg, sizeof(msg), "\"running\":\"%s\",", deviceRunning ? "ON" : "OFF");
  if (accelOk) jsonAdd(msg, sizeof(msg), "\"vibration\":%.3f,", statusMaxRms);
  if (vibLastRun.n) jsonAdd(msg, sizeof(msg), "\"last_run_s\":%.1f,", lastRunSeconds);
  jsonAdd(msg, sizeof(msg), "\"cycles\":%lu,\"sensor_problem\":\"%s\",", (unsigned long)cycleCount, accelOk ? "OFF" : "ON");
  jsonAdd(msg, sizeof(msg), "\"rssi\":%d,\"uptime_s\":%lu,\"version\":\"%s\"}", (int)WiFi.RSSI(),
          (unsigned long)(now / 1000), FIRMWARE_VERSION);
  return mqtt.publish(topic, msg, true);
}

// Once per 250 ms window: keeps the broker connection up and sends at most one
// message, so sampling resumes quickly.
void serviceMqtt(uint32_t now) {
  if (!net.mqttHost[0]) {
    if (mqtt.connected()) mqtt.disconnect();
    return;
  }
  if (WiFi.status() != WL_CONNECTED) return;
  if (!mqtt.connected()) {
    if (lastMqttAttemptMs && now - lastMqttAttemptMs < MQTT_RETRY_MS) return;
    lastMqttAttemptMs = now ? now : 1;
    char clientId[40], will[64];
    snprintf(clientId, sizeof(clientId), "devmon-%s", devName());
    snprintf(will, sizeof(will), "%s/status", mqttBase);
    mqtt.setServer(net.mqttHost, net.mqttPort);
    bool ok = mqtt.connect(clientId, net.mqttUser[0] ? net.mqttUser : nullptr, net.mqttUser[0] ? net.mqttPass : nullptr,
                           will, 0, true, "offline");
    if (!ok) {
      if (!mqttFailLogged) logf("[mqtt] can't connect to %s:%u: %s (state %d); retrying every %lu s", net.mqttHost,
                                (unsigned)net.mqttPort, mqttProblem(), mqtt.state(), (unsigned long)(MQTT_RETRY_MS / 1000));
      mqttFailLogged = true;
      return;
    }
    mqttFailLogged = false;
    logf("[mqtt] connected to %s:%u", net.mqttHost, (unsigned)net.mqttPort);
    mqtt.publish(will, "online", true);
    mqttDiscoveryIdx = 0;
    mqttDirty = true;
    return;
  }
  mqtt.loop();
  if (mqttDiscoveryIdx >= 0) {
    if (!publishHaDiscovery(HA_ENTITIES[mqttDiscoveryIdx]))
      logf("[mqtt] discovery for %s not sent", HA_ENTITIES[mqttDiscoveryIdx].id);
    if (++mqttDiscoveryIdx >= HA_ENTITY_COUNT) mqttDiscoveryIdx = -1;
    return;
  }
  if (mqttDirty || now - lastMqttStateMs >= MQTT_STATE_MS) {
    if (publishMqttState(now)) mqttDirty = false;
    lastMqttStateMs = now;
  }
}

// ==========================================
// Web page
// ==========================================
void jsonNum(char *buf, size_t len, const char *key, float v, int decimals, bool valid = true) {
  if (valid && !isnan(v)) jsonAdd(buf, len, "\"%s\":%.*f,", key, decimals, v);
  else jsonAdd(buf, len, "\"%s\":null,", key);
}

void jsonAcc(char *buf, size_t len, const char *key, const RmsAcc &a) {
  jsonAdd(buf, len, "\"%s\":{\"n\":%lu,\"avg\":%.3f,\"min\":%.3f,\"max\":%.3f},", key, (unsigned long)a.n, a.avg(), a.mn,
          a.mx);
}

void handleWebStatus() {
  static char j[1800];
  uint32_t now = millis();
  j[0] = 0;
  jsonAdd(j, sizeof(j), "{\"device\":\"%s\",\"version\":\"%s\",\"time\":\"%s\",\"uptime_s\":%lu,\"sensor\":\"%s\",",
          devName(), FIRMWARE_VERSION, logTimestamp(), (unsigned long)(now / 1000), accelOk ? accelModel() : "none");
  jsonAdd(j, sizeof(j), "\"state\":\"%s\",", !accelOk ? "no-accel" : deviceRunning ? "running" : "idle");
  jsonNum(j, sizeof(j), "rms", lastRms, 3);
  jsonNum(j, sizeof(j), "rms_max", statusMaxRms, 3);
  jsonAdd(j, sizeof(j), "\"run_s\":%lu,", deviceRunning ? (unsigned long)((now - runStartMs) / 1000) : 0UL);
  jsonAdd(j, sizeof(j), "\"rssi\":%d,\"heap\":%lu,\"iq\":%d,\"cycles\":%lu,\"total_run_s\":%lu,", (int)WiFi.RSSI(),
          (unsigned long)ESP.getFreeHeap(), iqCount, (unsigned long)cycleCount, (unsigned long)(totalRunMs / 1000));
  jsonAdd(j, sizeof(j), "\"idle\":{\"n\":%lu,\"avg\":%.3f,\"max\":%.3f},", (unsigned long)vibIdleBoot.n,
          vibIdleBoot.avg(), vibIdleBoot.mx);
  jsonAdd(j, sizeof(j), "\"last_run\":{\"n\":%lu,\"avg\":%.3f,\"min\":%.3f,\"max\":%.3f,\"seconds\":%.1f,\"ago_s\":%lu},",
          (unsigned long)vibLastRun.n, vibLastRun.avg(), vibLastRun.mn, vibLastRun.mx, lastRunSeconds,
          (unsigned long)((now - lastRunEndMs) / 1000));
  jsonAdd(j, sizeof(j), "\"cal\":{\"phase\":%d,\"left_s\":%lu,", (int)calPhase,
          calPhase ? (unsigned long)(((int32_t)(calEndMs - now) > 0 ? calEndMs - now : 0) / 1000) : 0UL);
  jsonAcc(j, sizeof(j), "idle", calIdle);
  jsonAcc(j, sizeof(j), "run", calRun);
  j[strlen(j) - 1] = 0;  // drop the trailing comma
  jsonAdd(j, sizeof(j), "},");
  jsonAdd(j, sizeof(j), "\"cfg\":{\"on\":%.3g,\"off\":%.3g,\"run_ms\":%lu,\"stop_ms\":%lu},", cfg.onRms, cfg.offRms,
          (unsigned long)cfg.runConfirmMs, (unsigned long)cfg.stopConfirmMs);
  // Secrets (ntfy topic, token, passwords) only say whether they're set: this
  // endpoint needs no login.
  jsonAdd(j, sizeof(j), "\"conn\":{\"wifi\":\"%s\",\"tz\":\"%s\",\"influx_url\":\"%s\",\"influx_token\":%s,"
          "\"ntfy_server\":\"%s\",\"ntfy\":%s,\"ntfy_run\":%s,\"ntfy_daily\":%s,\"mqtt_host\":\"%s\",\"mqtt_port\":%u,"
          "\"mqtt_user\":\"%s\",\"mqtt_pass\":%s,\"mqtt\":\"%s\"}}",
          WiFi.SSID().c_str(), net.tz, net.influxUrl, net.influxToken[0] ? "true" : "false", net.ntfyServer,
          net.ntfyTopic[0] ? "true" : "false", net.ntfyRun ? "true" : "false", net.ntfyDaily ? "true" : "false",
          net.mqttHost, (unsigned)net.mqttPort, net.mqttUser, net.mqttPass[0] ? "true" : "false",
          !net.mqttHost[0] ? "off" : mqtt.connected() ? "connected" : mqttProblem());
  web.sendHeader("Cache-Control", "no-store");
  web.send(200, "application/json", j);
}

void handleWebLog() {
  uint32_t since = web.hasArg("since") ? (uint32_t)strtoul(web.arg("since").c_str(), nullptr, 10) : 0;
  uint32_t oldest = logSeq > (uint32_t)LOG_LINES ? logSeq - LOG_LINES : 0;
  if (since < oldest || since > logSeq) since = oldest;
  String out;
  out.reserve(16 + (logSeq - since) * 90);
  out += logSeq;
  out += '\n';
  for (uint32_t i = since; i < logSeq; i++) {
    out += logRing[i % LOG_LINES];
    out += '\n';
  }
  web.sendHeader("Cache-Control", "no-store");
  web.send(200, "text/plain; charset=utf-8", out);
}

void sendMessagePage(int code, const char *title, const char *text, bool reload = false) {
  String page = F("<!doctype html><meta charset=utf-8><meta name=viewport content=\"width=device-width,initial-scale=1\">");
  if (reload) page += F("<meta http-equiv=refresh content=\"25;url=/\">");
  page += F("<body style=\"font:16px system-ui;padding:24px\"><h3>");
  page += title;
  page += F("</h3><p>");
  page += text;
  page += F("</p><p><a href=\"/\">Back</a></p>");
  web.send(code, "text/html; charset=utf-8", page);
}

void sendSettingsError(const char *problem) { sendMessagePage(400, "Not saved", problem); }

// Digest authentication, so the admin password itself never crosses the
// network: user "admin" and the admin password.
bool webAuthorized() {
  if (web.authenticate("admin", net.adminPass)) return true;
  web.requestAuthentication(DIGEST_AUTH, "Device Monitor");
  return false;
}

void redirectHome(const char *query) {
  web.sendHeader("Location", String("/?") + query);
  web.send(303, "text/plain", "");
}

// POST /settings: thresholds and confirm times.
void handleWebSettings() {
  if (!webAuthorized()) return;
  if (web.hasArg("reset")) {
    applySettings(DEFAULT_SETTINGS, true);
    return redirectHome("reset=1");
  }
  for (const char *k : {"on", "off", "run_s", "stop_s"}) {
    if (!web.hasArg(k) || !web.arg(k).length()) return sendSettingsError("Every field needs a number.");
  }
  Settings c;
  c.onRms         = web.arg("on").toFloat();
  c.offRms        = web.arg("off").toFloat();
  c.runConfirmMs  = (uint32_t)lroundf(constrain(web.arg("run_s").toFloat(), 0.0f, 100000.0f) * 1000.0f);
  c.stopConfirmMs = (uint32_t)lroundf(constrain(web.arg("stop_s").toFloat(), 0.0f, 100000.0f) * 1000.0f);
  const char *problem = settingsProblem(c);
  if (problem) return sendSettingsError(problem);
  applySettings(c, false);
  redirectHome("saved=1");
}

// POST /calibrate: phase=idle|run starts a capture, phase=stop ends it.
// Harmless, so no login.
void handleWebCalibrate() {
  String phase = web.arg("phase");
  uint32_t secs = web.hasArg("secs") ? (uint32_t)web.arg("secs").toInt() : CAL_DEFAULT_MS / 1000;
  secs = constrain(secs, 5UL, 600UL);
  if (phase == "idle" || phase == "run") {
    if (!accelOk) return sendSettingsError("The accelerometer is not answering, so there is nothing to measure.");
    calPhase = phase == "idle" ? CAL_IDLE : CAL_RUN;
    (calPhase == CAL_IDLE ? calIdle : calRun).reset();
    calEndMs = millis() + secs * 1000;
    logf("[cal] measuring %s vibration for %lu s", phase == "idle" ? "idle" : "running", (unsigned long)secs);
  } else {
    if (calPhase != CAL_NONE) logf("[cal] capture stopped");
    calPhase = CAL_NONE;
  }
  web.sendHeader("Cache-Control", "no-store");
  web.send(200, "text/plain", "ok");
}

// POST /device: name and time zone. A new name restarts the board (it's the
// network name), after removing the old name's Home Assistant entries.
void handleWebDevice() {
  if (!webAuthorized()) return;
  String name = lowerTrim(web.arg("name"));
  String tz = web.arg("tz");
  tz.trim();
  if (!validName(name.c_str()))
    return sendSettingsError("The name must be 1 to 24 characters: lowercase letters, digits and -, not at either end.");
  if (!tz.length() || tz.length() >= sizeof(net.tz) || !plainText(tz.c_str()))
    return sendSettingsError("The time zone must be a POSIX TZ string such as EST5EDT,M3.2.0,M11.1.0/2.");
  bool renamed = name != net.name;
  if (tz != net.tz) {
    snprintf(net.tz, sizeof(net.tz), "%s", tz.c_str());
    configTzTime(net.tz, NTP_SERVER);
    logf("[cfg] time zone set to %s", net.tz);
  }
  if (renamed) {
    char oldName[sizeof(net.name)];
    snprintf(oldName, sizeof(oldName), "%s", net.name);
    mqttForgetName(oldName);
    snprintf(net.name, sizeof(net.name), "%s", name.c_str());
    logf("[cfg] renamed %s -> %s; restarting", oldName, net.name);
  }
  saveNetConfig();
  if (!renamed) return redirectHome("dev=1");
  String text = String("Restarting as <b>") + net.name + "</b>. In about 20 seconds, open <a href=\"http://" + net.name +
                ".local/\">http://" + net.name + ".local/</a>.";
  sendMessagePage(200, "Renamed", text.c_str());
  restartAtMs = millis() + 1000;
  restartReason = REASON_USER;
}

// POST /connections: InfluxDB, ntfy, MQTT, admin password. Secret fields left
// empty keep their saved value.
void handleWebConnections() {
  if (!webAuthorized()) return;
  NetConfig c = net;
  String iurl = web.arg("influx_url"), itok = web.arg("influx_token"), nsrv = web.arg("ntfy_server"),
         topic = web.arg("ntfy"), host = web.arg("mqtt_host"), user = web.arg("mqtt_user"), pass = web.arg("mqtt_pass"),
         admin = web.arg("admin"), port = web.arg("mqtt_port");
  iurl.trim(); itok.trim(); nsrv.trim(); topic.trim(); host.trim(); user.trim();
  while (nsrv.endsWith("/")) nsrv.remove(nsrv.length() - 1);
  if (iurl.length() >= sizeof(c.influxUrl) || !plainText(iurl.c_str()) ||
      (iurl.length() && !iurl.startsWith("http://") && !iurl.startsWith("https://")))
    return sendSettingsError("The InfluxDB address must start with http:// or https:// (or be empty to turn it off).");
  if (itok.length() >= sizeof(c.influxToken) || !plainText(itok.c_str()))
    return sendSettingsError("The InfluxDB token is too long or has spaces or quotes.");
  if (!nsrv.length()) nsrv = NTFY_SERVER;
  if (nsrv.length() >= sizeof(c.ntfyServer) || !plainText(nsrv.c_str()) ||
      (!nsrv.startsWith("http://") && !nsrv.startsWith("https://")))
    return sendSettingsError("The ntfy server must start with https:// (or http://).");
  if (topic.length() >= sizeof(c.ntfyTopic) || !plainText(topic.c_str()) || topic.indexOf('/') >= 0)
    return sendSettingsError("The ntfy topic can only contain letters, digits, - and _.");
  if (host.length() >= sizeof(c.mqttHost) || !plainText(host.c_str()) || host.indexOf('/') >= 0 || host.indexOf(':') >= 0)
    return sendSettingsError("The MQTT broker must be a host name or IP address only (no mqtt:// and no port).");
  long p = port.length() ? port.toInt() : 1883;
  if (p < 1 || p > 65535) return sendSettingsError("The MQTT port must be between 1 and 65535.");
  if (user.length() >= sizeof(c.mqttUser) || !plainText(user.c_str()))
    return sendSettingsError("The MQTT user name is too long or has unusual characters.");
  if (pass.length() >= sizeof(c.mqttPass) || !plainText(pass.c_str()))
    return sendSettingsError("The MQTT password is too long or has spaces, quotes or a backslash.");
  if (admin.length() && (admin.length() < 8 || admin.length() >= sizeof(c.adminPass) || !plainText(admin.c_str())))
    return sendSettingsError("A new admin password must be 8 to 32 characters, with no spaces, quotes or backslash.");

  snprintf(c.influxUrl, sizeof(c.influxUrl), "%s", iurl.c_str());
  if (web.hasArg("influx_token_off") || !iurl.length()) c.influxToken[0] = 0;
  else if (itok.length()) snprintf(c.influxToken, sizeof(c.influxToken), "%s", itok.c_str());
  snprintf(c.ntfyServer, sizeof(c.ntfyServer), "%s", nsrv.c_str());
  if (web.hasArg("ntfy_off")) c.ntfyTopic[0] = 0;
  else if (topic.length()) snprintf(c.ntfyTopic, sizeof(c.ntfyTopic), "%s", topic.c_str());
  c.ntfyRun = web.hasArg("ntfy_run");
  c.ntfyDaily = web.hasArg("ntfy_daily");
  snprintf(c.mqttHost, sizeof(c.mqttHost), "%s", host.c_str());
  c.mqttPort = (uint16_t)p;
  snprintf(c.mqttUser, sizeof(c.mqttUser), "%s", user.c_str());
  if (!user.length()) c.mqttPass[0] = 0;
  else if (pass.length()) snprintf(c.mqttPass, sizeof(c.mqttPass), "%s", pass.c_str());
  if (admin.length()) snprintf(c.adminPass, sizeof(c.adminPass), "%s", admin.c_str());

  bool mqttChanged = strcmp(c.mqttHost, net.mqttHost) || c.mqttPort != net.mqttPort || strcmp(c.mqttUser, net.mqttUser) ||
                     strcmp(c.mqttPass, net.mqttPass);
  net = c;
  saveNetConfig();
  if (mqttChanged) {
    mqtt.disconnect();
    lastMqttAttemptMs = 0;
    mqttFailLogged = false;
  }
  if (!net.influxUrl[0]) iqCount = 0;
  if (!net.ntfyTopic[0]) ntfyCount = 0;
  lastIqFailMs = 0;
  logNetConfig("connections changed");
  redirectHome("conn=1");
}

// POST /test: sends a test push and a test point, so the connections can be
// checked without waiting for a run.
void handleWebTest() {
  if (!webAuthorized()) return;
  notify(PRIO_INFO, "test_tube", ": test", "Test push from %s (%s), firmware %s.", devName(), WiFi.localIP().toString().c_str(),
         FIRMWARE_VERSION);
  influxPoint("appliance_test", "value=1i");
  mqttDirty = true;
  redirectHome("test=1");
}

// POST /wifi: restart into the setup portal (to move to another network).
void handleWebWifi() {
  if (!webAuthorized()) return;
  prefs.begin(NVS_NS, false);
  prefs.putBool("portal", true);
  prefs.end();
  char ap[32];
  apName(ap, sizeof(ap));
  String text = String("The board is restarting into its setup portal. Join the Wi-Fi network <b>") + ap +
                "</b> from a phone and pick the new network. If nobody does within 5 minutes it goes back to the "
                "current network.";
  sendMessagePage(200, "Wi-Fi setup", text.c_str());
  restartAtMs = millis() + 1000;
  restartReason = REASON_USER;
}

void handleWebRestart() {
  if (!webAuthorized()) return;
  sendMessagePage(200, "Restarting", "Back in about 20 seconds.", true);
  restartAtMs = millis() + 1000;
  restartReason = REASON_USER;
}

// Firmware upload from the web page (POST /update, multipart, the .bin from
// .pio/build/devmon/firmware.bin). Same trial-and-rollback as ArduinoOTA.
bool uploadAuthorized = false;
String uploadError;

void handleWebUpdateUpload() {
  HTTPUpload &up = web.upload();
  if (up.status == UPLOAD_FILE_START) {
    uploadError = "";
    uploadAuthorized = web.authenticate("admin", net.adminPass);
    if (!uploadAuthorized) return;
    logf("[OTA] web upload starting: %s", up.filename.c_str());
    saveHealthBeforeUpdate();
    if (!Update.begin(UPDATE_SIZE_UNKNOWN)) uploadError = Update.errorString();
  } else if (up.status == UPLOAD_FILE_WRITE) {
    esp_task_wdt_reset();
    if (!uploadAuthorized || uploadError.length()) return;
    if (Update.write(up.buf, up.currentSize) != up.currentSize) uploadError = Update.errorString();
  } else if (up.status == UPLOAD_FILE_END) {
    if (!uploadAuthorized || uploadError.length()) return;
    if (!Update.end(true)) uploadError = Update.errorString();
    else logf("[OTA] web upload complete: %u bytes", (unsigned)up.totalSize);
  } else if (up.status == UPLOAD_FILE_ABORTED) {
    Update.abort();
    uploadError = "upload aborted";
  }
}

void handleWebUpdateDone() {
  if (!uploadAuthorized) {
    if (!webAuthorized()) return;  // asks for the password; the browser then re-sends the file
  }
  if (uploadError.length() || !Update.isFinished()) {
    String text = String("The update failed: ") + (uploadError.length() ? uploadError : String("incomplete upload")) +
                  ". The board is still running the old firmware.";
    logf("[OTA] web upload failed: %s", uploadError.c_str());
    return sendMessagePage(400, "Update failed", text.c_str());
  }
  sendMessagePage(200, "Update received",
                  "Restarting into the new firmware. It runs as a trial for 3 minutes and rolls back by itself if it "
                  "isn't healthy. This page reloads in 25 seconds.", true);
  otaDone = true;
}

void setupWeb() {
  web.enableDelay(false);  // handleClient() must return at once when nobody is connected
  web.on("/", HTTP_GET, []() { web.send_P(200, "text/html; charset=utf-8", WEB_PAGE); });
  web.on("/api/status", HTTP_GET, handleWebStatus);
  web.on("/api/log", HTTP_GET, handleWebLog);
  web.on("/settings", HTTP_POST, handleWebSettings);
  web.on("/calibrate", HTTP_POST, handleWebCalibrate);
  web.on("/device", HTTP_POST, handleWebDevice);
  web.on("/connections", HTTP_POST, handleWebConnections);
  web.on("/test", HTTP_POST, handleWebTest);
  web.on("/wifi", HTTP_POST, handleWebWifi);
  web.on("/restart", HTTP_POST, handleWebRestart);
  web.on("/update", HTTP_POST, handleWebUpdateDone, handleWebUpdateUpload);
  web.onNotFound([]() { web.send(404, "text/plain", "Not found"); });
  web.begin();
  MDNS.addService("http", "tcp", 80);
  logf("[web] ready: http://%s.local/ (http://%s/)", devName(), WiFi.localIP().toString().c_str());
}

void serviceWeb() {
  if (WiFi.status() != WL_CONNECTED) return;
  for (int i = 0; i < 3; i++) web.handleClient();
}

void checkRestartRequest(uint32_t now) {
  if (!restartAtMs || (int32_t)(now - restartAtMs) < 0) return;
  flushQueues(3000);
  restartWithReason(restartReason);
}

// ==========================================
// Arduino entry points
// ==========================================
void setup(void) {
  Serial.begin(115200);
  Serial.setTxTimeoutMs(0);  // never block on a stalled USB host
  ledWrite(LED_WHITE);
  bool forcePortal = checkDoubleReset();
  delay(2000);               // give USB-CDC time to attach so early messages aren't lost
  Serial.println();
  Serial.println(BANNER);

  prefs.begin(NVS_NS, false);
  lastRebootDay = prefs.getInt("last_reboot_day", -1);
  lastRecordedState = prefs.getInt("last_state", -1);
  prefs.end();
  WiFi.mode(WIFI_STA);        // so the MAC (for the default name) is readable
  loadNetConfig();
  // Before any timestamped logging: the RTC survives a soft reset, so time()
  // can already be valid and would otherwise be read as UTC.
  configTzTime(net.tz, NTP_SERVER);
  logf("--- Device Monitor \"%s\" v%s ---", devName(), FIRMWARE_VERSION);
  loadSettings();
  logNetConfig("connections");

  checkUnexpectedReset();
  checkOtaState();
  if (!forcePortal) finishDoubleResetWindow();
  else {
    prefs.begin(NVS_NS, false);
    prefs.putBool("drd", false);
    prefs.end();
  }

  setupWiFi(forcePortal);
  setupTime();
  checkBootEpoch();
  setupOta();
  setupWeb();
  setupMqtt();
  setupSensor();
  reportBoot();
  updateStatusLed();

  // Hardware backstop for a hung loop (stuck I2C/network/USB call). Armed last,
  // since setup() legitimately blocks (the portal, Wi-Fi, NTP).
  esp_task_wdt_config_t wdtCfg = {
    .timeout_ms = 30000,
    .idle_core_mask = 0,
    .trigger_panic = true,
  };
  if (esp_task_wdt_reconfigure(&wdtCfg) != ESP_OK) esp_task_wdt_init(&wdtCfg);
  esp_task_wdt_add(NULL);

  lastIqOkMs = millis();
  logf("Monitoring...");
  nextSampleUs = micros();
}

void loop(void) {
  esp_task_wdt_reset();
  uint32_t nowUs = micros();
  if ((int32_t)(nowUs - nextSampleUs) < 0) return;
  nextSampleUs += SAMPLE_PERIOD_US;
  if ((int32_t)(nowUs - nextSampleUs) > 0) nextSampleUs = nowUs + SAMPLE_PERIOD_US;  // fell behind

  float x = bx, y = by, z = bz;  // no signal while the accelerometer is missing
  if (accelOk) {
    if (readSample(x, y, z)) {
      accelReadFails = 0;
    } else {
      x = bx; y = by; z = bz;
      if (++accelReadFails >= SAMPLE_FAIL_LIMIT) {
        accelReadFails = 0;
        accelLost("stopped responding on I2C (reads failing)");
      }
    }
  }

  float dx = x - bx, dy = y - by, dz = z - bz;
  sumSq += dx * dx + dy * dy + dz * dz;
  bx += BASELINE_ALPHA * dx;
  by += BASELINE_ALPHA * dy;
  bz += BASELINE_ALPHA * dz;

  if (++sampleCount < SAMPLES_PER_WINDOW) return;

  float rms = sqrt(sumSq / sampleCount);
  sumSq = 0;
  sampleCount = 0;

  // A working accelerometer always has some noise; an exactly constant signal
  // means it has stopped measuring.
  if (accelOk && rms < 0.0005f) {
    if (++flatWindows >= FLAT_WINDOW_LIMIT) {
      flatWindows = 0;
      accelLost("reads a constant (not measuring)");
    }
  } else {
    flatWindows = 0;
  }

  // Once per 250 ms window.
  uint32_t now = millis();
  processWindow(rms, now);
  updateStatusLed();
  checkBootEpoch();
  checkPeriodicReading(now);
  serviceNetwork(now);
  serviceOta();
  serviceWeb();
  serviceMqtt(now);
  checkWiFiWatchdog();
  checkSensorWatchdog(now);
  checkInfluxWatchdog(now);
  checkBootStateCorrection(now);
  checkOtaTrial(now);
  checkDailyReboot();
  checkRestartRequest(now);

  if (now - lastStatusMs >= 1000) {
    lastStatusMs = now;
    logKeep = false;  // once a second: serial only, it would push everything else out of the web log
    logf("rms=%.3f max=%.3f loud=%d state=%s wifi=%s iq=%d", lastRms, maxRmsSinceStatus, loudWindowsSinceStatus,
         !accelOk ? "no-accel" : deviceRunning ? "RUNNING" : "idle", WiFi.status() == WL_CONNECTED ? "up" : "down",
         iqCount);
    logKeep = true;
    statusMaxRms = maxRmsSinceStatus;
    maxRmsSinceStatus = 0;
    loudWindowsSinceStatus = 0;
  }
}
