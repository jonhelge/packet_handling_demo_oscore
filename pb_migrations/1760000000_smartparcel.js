/// <reference path="../../../pb_data/types.d.ts" />
//
// SmartParcel product schema: device profile + classifications collection and
// indexes for a fresh oscore-server install.

migrate(
  (app) => {
    const profiles = app.findCollectionByNameOrId("device_profiles");
    const profile = new Record(profiles);
    profile.set("name", "smartparcel");
    profile.set("platform", "nordic-nrf91");
    profile.set("metrics", [
      { key: "30", name: "class_idx", label: "Class index", unit: "" },
      { key: "31", name: "confidence", label: "Confidence", unit: "" },
      { key: "32", name: "seq", label: "Event sequence", unit: "" },
      { key: "33", name: "age_ms", label: "Inference age", unit: "ms" },
      { key: "34", name: "rtt_ms", label: "Prior RTT", unit: "ms" },
      { key: "35", name: "probs_pack", label: "Probabilities packed", unit: "" },
    ]);
    app.save(profile);

    const col = new Collection({
      name: "classifications",
      type: "base",
      listRule: "",
      viewRule: "",
      createRule: null,
      updateRule: null,
      deleteRule: null,
      fields: [
        { name: "hw_id", type: "text", required: true },
        { name: "state", type: "text", required: true },
        {
          name: "class_idx",
          type: "number",
          required: false,
          min: 0,
          max: 6,
          onlyInt: true,
        },
        { name: "confidence", type: "number", required: false, min: 0, max: 1 },
        { name: "probabilities", type: "json" },
        { name: "seq", type: "number", required: true },
        { name: "device_ts", type: "number" },
        { name: "server_ms", type: "number", required: true },
        { name: "age_ms", type: "number" },
        { name: "rtt_ms", type: "number" },
        { name: "browser_ms", type: "number" },
        { name: "telemetry", type: "text" },
      ],
    });
    col.addIndex("idx_classifications_telemetry", true, "telemetry", "telemetry != ''");
    col.addIndex("idx_classifications_telemetry_lookup", false, "telemetry", "");
    col.addIndex("idx_classifications_hw_seq_ts", false, "hw_id, seq, device_ts", "");
    app.save(col);

    const tel = app.findCollectionByNameOrId("telemetry");
    tel.addIndex("idx_telemetry_received_at", false, "received_at", "");
    app.save(tel);
  },
  (app) => {
    try {
      const p = app.findFirstRecordByFilter("device_profiles", "name = 'smartparcel'");
      app.delete(p);
    } catch (_) {}
    try {
      const col = app.findCollectionByNameOrId("classifications");
      app.delete(col);
    } catch (_) {}
    try {
      const tel = app.findCollectionByNameOrId("telemetry");
      tel.removeIndex("idx_telemetry_received_at");
      app.save(tel);
    } catch (_) {}
  }
);
