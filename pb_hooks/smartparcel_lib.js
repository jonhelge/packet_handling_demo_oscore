/** Shared SmartParcel projection helpers (required from *.pb.js runtimes). */

const CLASS_IDX_TO_STATE = [
  "idle",
  "shaking",
  "impact",
  "freefall",
  "carrying",
  "car",
  "placed",
];

const CLASS_LABELS = {
  idle: "Idle",
  carrying: "Carrying",
  car: "In Car",
  shaking: "Shaking",
  impact: "Impact",
  freefall: "Free Fall",
  placed: "Placed",
};

function jsonField(rec, name) {
  // Prefer getString + parse (go/examples/water-temp). Fall back when the driver
  // already decoded JSON — but never treat a String object as a map (index keys).
  try {
    const s = rec.getString(name);
    if (s && (s[0] === "{" || s[0] === "[")) {
      return JSON.parse(s);
    }
  } catch (_) {}
  try {
    const v = rec.get(name);
    if (v == null) return {};
    if (typeof v === "string") return v ? JSON.parse(v) : {};
    const tag = Object.prototype.toString.call(v);
    if (tag === "[object String]") return v.length ? JSON.parse(String(v)) : {};
    if (tag === "[object Object]") {
      return JSON.parse(JSON.stringify(v));
    }
  } catch (_) {}
  return {};
}

function numField(data, key) {
  let v = data[String(key)];
  if (v === null || v === undefined) {
    v = data[key];
  }
  if (v === null || v === undefined) {
    return null;
  }
  const n = typeof v === "number" ? v : Number(v);
  return Number.isFinite(n) ? n : null;
}

function unpackProbabilities(packed) {
  const out = {};
  const n = Number(packed);
  if (!Number.isFinite(n)) return out;
  for (let i = 0; i < CLASS_IDX_TO_STATE.length; i++) {
    const b = Math.floor(n / Math.pow(256, i)) % 256;
    out[CLASS_IDX_TO_STATE[i]] = b / 255;
  }
  return out;
}

function stateFromClassIdx(idx) {
  if (idx >= 0 && idx < CLASS_IDX_TO_STATE.length) {
    return CLASS_IDX_TO_STATE[idx];
  }
  return "idle";
}

/** True when payload carries SmartParcel classification keys (30 + 32). Class 0 is valid. */
function isSmartparcelClassification(data) {
  return numField(data, 30) !== null && numField(data, 32) !== null;
}

function percentile(sorted, p) {
  if (!sorted.length) return 0;
  const i = Math.ceil((p / 100) * sorted.length) - 1;
  return sorted[Math.max(0, Math.min(sorted.length - 1, i))];
}

function latencyStats(values) {
  const sorted = values.filter((v) => Number.isFinite(v)).sort((a, b) => a - b);
  if (!sorted.length) {
    return { count: 0, p50: 0, p95: 0, max: 0 };
  }
  return {
    count: sorted.length,
    p50: percentile(sorted, 50),
    p95: percentile(sorted, 95),
    max: sorted[sorted.length - 1],
  };
}

function recordExists(app, filter, params) {
  try {
    return !!app.findFirstRecordByFilter("classifications", filter, params);
  } catch (_) {
    return false;
  }
}

// Keyed on the source telemetry row: the device's seq restarts at 1 on reboot.
// Rows projected before the telemetry link existed are matched on
// hw_id + seq + device_ts, which also differs across reboots.
function classificationExists(app, telemetryId, hwId, seq, deviceTs) {
  if (telemetryId && recordExists(app, "telemetry = {:t}", { t: telemetryId })) {
    return true;
  }
  return recordExists(
    app,
    "telemetry = '' && hw_id = {:hw} && seq = {:seq} && device_ts = {:ts}",
    { hw: hwId, seq: seq, ts: deviceTs ?? 0 }
  );
}

/**
 * Create a classifications row from decoded telemetry.data (no nested device saves).
 * Returns true if a row was created. skipDedupe is for the live create hook: the
 * telemetry row was just inserted, so no classification can reference it yet, and
 * the unique idx_classifications_telemetry still rejects a racing backfill insert.
 */
function projectClassification(app, telemetryId, hwId, data, serverMs, skipDedupe) {
  if (!isSmartparcelClassification(data)) {
    return false;
  }

  const classIdx = numField(data, 30);
  const seq = numField(data, 32);
  if (classIdx === null || seq === null) {
    return false;
  }

  const tsSec = numField(data, 3);
  const deviceTs = tsSec !== null ? tsSec * 1000 : null;

  if (!skipDedupe && classificationExists(app, telemetryId, hwId, seq, deviceTs)) {
    return false;
  }

  const confidence = numField(data, 31) ?? 0;
  const ageMs = numField(data, 33);
  const rttMs = numField(data, 34);
  const packed = numField(data, 35);
  const state = stateFromClassIdx(classIdx);
  const probabilities = unpackProbabilities(packed);

  const stamp =
    serverMs !== undefined && Number.isFinite(Number(serverMs))
      ? Number(serverMs)
      : Date.now();

  const col = app.findCollectionByNameOrId("classifications");
  const rec = new Record(col);
  rec.set("telemetry", telemetryId || "");
  rec.set("hw_id", hwId);
  rec.set("state", state);
  rec.set("class_idx", classIdx);
  rec.set("confidence", confidence);
  rec.set("probabilities", probabilities);
  rec.set("seq", seq);
  rec.set("device_ts", deviceTs);
  rec.set("server_ms", stamp);
  rec.set("age_ms", ageMs);
  rec.set("rtt_ms", rttMs);
  app.save(rec);
  return true;
}

/** telemetry onRecordAfterCreateSuccess — must live here (isolated hook runtimes). */
function handleTelemetryCreated(e) {
  const app = e.app;
  const tel = e.record;
  const data = jsonField(tel, "data");

  let deviceRec;
  try {
    deviceRec = app.findRecordById("devices", tel.get("device"));
  } catch (_) {
    return;
  }

  const hwId = deviceRec.get("hw_id") || "";
  if (!hwId) {
    return;
  }

  projectClassification(app, tel.id, hwId, data, undefined, true);
}

/** Backfill: scan recent telemetry and project any missing classifications. */
function backfillRecentTelemetry(app, limit) {
  const n = limit || 30;
  let rows = [];
  let fetchError = null;
  try {
    rows = app.findRecordsByFilter("telemetry", "id != ''", "-received_at", n, 0);
  } catch (err) {
    fetchError = String(err);
    try {
      rows = app.findRecordsByFilter("telemetry", "id != ''", "-ts", n, 0);
    } catch (err2) {
      return { created: 0, scanned: 0, error: fetchError || String(err2) };
    }
  }

  let created = 0;
  let smartparcelRows = 0;
  for (const tel of rows) {
    const data = jsonField(tel, "data");
    if (!isSmartparcelClassification(data)) {
      continue;
    }
    smartparcelRows++;
    let deviceRec;
    try {
      deviceRec = app.findRecordById("devices", tel.get("device"));
    } catch (_) {
      continue;
    }
    const hwId = deviceRec.get("hw_id") || "";
    if (!hwId) {
      continue;
    }
    const received = tel.get("received_at");
    let serverMs;
    if (received && typeof received === "object" && received.time) {
      serverMs = new Date(received.time).getTime();
    } else if (received) {
      serverMs = new Date(String(received)).getTime();
    }
    try {
      if (projectClassification(app, tel.id, hwId, data, serverMs)) {
        created++;
      }
    } catch (err) {
      console.error("smartparcel backfill:", err);
    }
  }
  const out = { created, scanned: rows.length, smartparcel_rows: smartparcelRows };
  if (fetchError) out.fetch_warn = fetchError;
  return out;
}

module.exports = {
  CLASS_IDX_TO_STATE,
  CLASS_LABELS,
  jsonField,
  numField,
  unpackProbabilities,
  stateFromClassIdx,
  isSmartparcelClassification,
  latencyStats,
  handleTelemetryCreated,
  backfillRecentTelemetry,
};
