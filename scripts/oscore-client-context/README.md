# OSCORE client context for `sim-parcel.py`

This directory holds the **aiocoap** OSCORE client credentials for one provisioned
device (same role as `settings.json` on the server side, but for the client).

After provisioning:

```bash
./scripts/provision-parcel.sh sim-parcel-01 "Simulator"
```

Export the device's OSCORE material into aiocoap format. From the monorepo
`aiocoap` tooling, or hand-build `settings.json` from the provision JSON
(`master_secret`, `master_salt`, `sender_id`, `recipient_id`).

Quick path if you have the oscore_pocketbase repo checked out:

```bash
# Example: copy an existing interop client context and align hw_id with provision
cp -r /path/to/oscore_pocketbase/aiocoap/contexts/client/* .
```

Then reset `sequence.json` if the server replay state was cleared.

Files expected here:

- `settings.json` — OSCORE security context
- `sequence.json` — sender sequence (optional; created on first send)

The simulated device `hw_id` must match the provisioned record and use profile
`smartparcel`.
