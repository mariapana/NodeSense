import os
import time
import json
import socket
import requests
import psutil
from datetime import datetime, timezone

# ================= CONFIG =================
NODE_ID = os.getenv("NODE_ID", socket.gethostname())
COLLECTOR_URL = os.getenv("COLLECTOR_URL", "http://collector:3000/ingest")
INTERVAL = int(os.getenv("INTERVAL", "5"))


# ================= METRICS =================
def collect_metrics():
    cpu = psutil.cpu_percent(interval=None)

    mem = psutil.virtual_memory()

    load_avg = psutil.getloadavg()[0]

    metrics = [
        {"name": "cpu_usage", "value": cpu, "unit": "%"},
        {
            "name": "mem_used",
            "value": human_bytes(mem.used),
            "unit": "bytes",
        },
        {
            "name": "mem_total",
            "value": human_bytes(mem.total),
            "unit": "bytes",
        },
        {
            "name": "load_avg_1m",
            "value": (load_avg / psutil.cpu_count()) * 100,
            "unit": "%",
        },
    ]

    return metrics


def human_bytes(num):
    for unit in ["B", "KB", "MB", "GB", "TB", "PB"]:
        if num < 1024:
            return f"{num:.2f} {unit}"
        num /= 1024


# ================= PAYLOAD =================
def build_payload():
    return {
        "node_id": NODE_ID,
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "metrics": collect_metrics(),
    }


# ================= LOOP =================
def run():
    print(f"[agent] starting node agent: node_id={NODE_ID}, interval={INTERVAL}s")
    print(f"[agent] sending metrics to {COLLECTOR_URL}")

    while True:
        payload = build_payload()
        print(json.dumps(payload, indent=2), flush=True)

        try:
            response = requests.post(COLLECTOR_URL, json=payload, timeout=3)
            print(f"[agent] sent metrics ({response.status_code})")
        except Exception as e:
            print(f"[agent] failed to send metrics: {e}")

        time.sleep(INTERVAL)


if __name__ == "__main__":
    run()
