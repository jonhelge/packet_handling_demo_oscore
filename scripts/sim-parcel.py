#!/usr/bin/env python3
"""SmartParcel OSCORE uplink simulator (POST /t with classification keys).

Requires: pip install cbor2 aiocoap filelock

After ./scripts/provision-parcel.sh, copy OSCORE client material into
scripts/oscore-client-context/ (settings.json + sequence.json). See
scripts/oscore-client-context/README.md.

  OSCORE_HOST=127.0.0.1 python3 scripts/sim-parcel.py --cycles 1
"""

from __future__ import annotations

import argparse
import asyncio
import os
import sys
import time

import cbor2
from aiocoap import Context, Message
from aiocoap.numbers import ContentFormat
from aiocoap.numbers.codes import Code

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
DEFAULT_CONTEXT = os.path.join(SCRIPT_DIR, "oscore-client-context")

KEY_TRANSPORT = 1
KEY_FW = 2
KEY_TS = 3
KEY_CLASS = 30
KEY_CONF = 31
KEY_SEQ = 32
KEY_AGE = 33
KEY_RTT = 34
KEY_PROBS = 35

STATES = ["idle", "shaking", "impact", "freefall", "carrying", "car", "placed"]


def pack_probs(class_idx: int, confidence: float) -> int:
    probs = [0.02] * 7
    probs[class_idx] = confidence
    total = sum(probs)
    packed = 0
    for i, p in enumerate(probs):
        b = int(round((p / total) * 255))
        packed |= b << (8 * i)
    return packed


async def send_one(protocol, base_uri: str, class_idx: int, seq: int, rtt_ms: int) -> int:
    conf = 0.92
    body = {
        KEY_TRANSPORT: 1,
        KEY_FW: "sim-parcel",
        KEY_TS: int(time.time()),
        KEY_CLASS: class_idx,
        KEY_CONF: conf,
        KEY_SEQ: seq,
        KEY_AGE: 12,
        KEY_RTT: rtt_ms,
        KEY_PROBS: pack_probs(class_idx, conf),
    }
    uri = f"{base_uri}/t"
    t0 = time.monotonic()
    request = Message(code=Code.POST, uri=uri, payload=cbor2.dumps(body))
    request.opt.content_format = ContentFormat.CBOR
    response = await protocol.request(request).response
    rtt = int((time.monotonic() - t0) * 1000)
    print(f"POST /t class={STATES[class_idx]} seq={seq} -> {response.code} rtt={rtt}ms")
    return rtt


async def main_async(args) -> None:
    ctx_dir = os.path.abspath(args.context)
    if not os.path.isdir(ctx_dir):
        print(f"Missing OSCORE context: {ctx_dir}", file=sys.stderr)
        print("See scripts/oscore-client-context/README.md", file=sys.stderr)
        sys.exit(1)

    host = args.host
    base_uri = f"coap://{host}"
    protocol = await Context.create_client_context()
    protocol.client_credentials.load_from_dict(
        {f"{base_uri}/*": {"oscore": {"basedir": ctx_dir}}}
    )
    try:
        seq = 0
        last_rtt = 0
        for _ in range(args.cycles):
            for class_idx in range(7):
                seq += 1
                last_rtt = await send_one(protocol, base_uri, class_idx, seq, last_rtt)
                if args.interval > 0:
                    await asyncio.sleep(args.interval)
    finally:
        await protocol.shutdown()


def main() -> None:
    parser = argparse.ArgumentParser(description="SmartParcel OSCORE uplink simulator")
    parser.add_argument("--host", default=os.environ.get("OSCORE_HOST", "127.0.0.1"))
    parser.add_argument("--context", default=os.environ.get("OSCORE_CONTEXT_DIR", DEFAULT_CONTEXT))
    parser.add_argument("--cycles", type=int, default=1)
    parser.add_argument("--interval", type=float, default=0.5)
    args = parser.parse_args()
    asyncio.run(main_async(args))


if __name__ == "__main__":
    main()
