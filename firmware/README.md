# Thingy:91 X firmware (SmartParcel / OSCORE)

`smartparcel_oscore.hex` is a merged image for the **nRF9151** on the Nordic Thingy:91 X.
It runs the on-device Neuton motion classifier and sends **classification changes only**
to your oscore-server over **OSCORE CoAP** (`POST /t`). There is no nRF Cloud traffic.

## Flash

Same hardware flow as the [nRF Cloud SmartParcel demo](https://github.com/jhn-nordic/packet_handling_demo/blob/main/firmware/README.md):

1. SWD from a debug probe (e.g. nRF9151 DK) to **P8**, Thingy powered over USB-C, **SW2** = nRF91.
2. Program the merged hex (not USB recovery):

```sh
nrfutil device list
nrfutil device program --firmware firmware/smartparcel_oscore.hex \
  --serial-number <JLINK_SERIAL> --traits jlink --x-family nrf91 \
  --options chip_erase_mode=ERASE_ALL,verify=VERIFY_READ,reset=RESET_SYSTEM
```

## Configure on the serial shell

After flash, LTE attach, then (once per device):

```
uart:~$ oscore provision <master_secret> <master_salt> <recipient_id> <sender_id>
uart:~$ smartparcel server <server-ipv4>
uart:~$ reboot
```

Use the dedicated **IPv4** of your Fly app (`fly ips list`) or your host's public IP
for docker compose. UDP **5683** must reach the server.

Detection starts automatically when the cloud connects. Only class changes at ≥90%
confidence are uplinked (CBOR keys 30–35).
