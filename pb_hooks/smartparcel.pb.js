/// <reference path="../../pb_data/types.d.ts" />

// Isolated hook runtime: require lib inside handler; call e.next() first; never
// app.save(devices) from telemetry AfterCreateSuccess (breaks later projections).
onRecordAfterCreateSuccess((e) => {
  e.next();
  try {
    require(`${__hooks}/smartparcel_lib.js`).handleTelemetryCreated(e);
  } catch (err) {
    console.error("smartparcel telemetry hook:", err);
  }
}, "telemetry");

// Safety net if a hook invocation fails silently (nested-save quirks).
cronAdd("smartparcel-backfill", "* * * * *", () => {
  try {
    require(`${__hooks}/smartparcel_lib.js`).backfillRecentTelemetry($app, 40);
  } catch (err) {
    console.error("smartparcel backfill cron:", err);
  }
});

routerAdd("GET", "/api/smartparcel/latency", (e) => {
  const lib = require(`${__hooks}/smartparcel_lib.js`);
  const device = e.request.url.query().get("device") || "";
  const limit = Math.min(parseInt(e.request.url.query().get("limit") || "100", 10), 500);

  let filter = "";
  if (device) {
    filter = `hw_id = '${device.replace(/'/g, "''")}'`;
  }

  const rows = e.app.findRecordsByFilter(
    "classifications",
    filter,
    "-server_ms",
    limit,
    0
  );

  const uplinkEst = [];
  const serverToBrowser = [];
  const e2e = [];

  for (const r of rows) {
    const age = r.get("age_ms");
    const rtt = r.get("rtt_ms");
    const serverMs = r.get("server_ms");
    const browserMs = r.get("browser_ms");
    if (age !== null && rtt !== null) {
      uplinkEst.push(Number(age) + Number(rtt) / 2);
    }
    if (serverMs !== null && browserMs !== null) {
      const leg = Number(browserMs) - Number(serverMs);
      serverToBrowser.push(leg);
      if (age !== null && rtt !== null) {
        e2e.push(Number(age) + Number(rtt) / 2 + leg);
      }
    }
  }

  return e.json(200, {
    device: device || null,
    uplink_estimate_ms: lib.latencyStats(uplinkEst),
    server_to_browser_ms: lib.latencyStats(serverToBrowser),
    end_to_end_ms: lib.latencyStats(e2e),
  });
});

routerAdd("POST", "/api/smartparcel/backfill", (e) => {
  const lib = require(`${__hooks}/smartparcel_lib.js`);
  return e.json(200, lib.backfillRecentTelemetry(e.app, 100));
});

routerAdd("POST", "/api/smartparcel/ack", (e) => {
  const body = e.requestInfo().body;
  const id = body.id;
  const browserMs = body.browser_ms;
  if (!id || browserMs === undefined) {
    return e.json(400, { error: "id and browser_ms required" });
  }
  try {
    const rec = e.app.findRecordById("classifications", id);
    rec.set("browser_ms", Number(browserMs));
    e.app.save(rec);
    return e.json(200, { ok: true });
  } catch (err) {
    return e.json(404, { error: String(err) });
  }
});
