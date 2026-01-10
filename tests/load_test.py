import requests
import time
import concurrent.futures
import sys
import os
import random

# Config
GATEWAY_URL = os.getenv("GATEWAY_URL", "http://gateway:8000")
TOKEN = sys.argv[1] if len(sys.argv) > 1 else ""
NUM_NODES = 50
DURATION_SEC = 30
INTERVAL = 1.0  # Send every 1s per node

if not TOKEN:
    print("Usage: python load_test.py <TOKEN>")
    sys.exit(1)

print(f"--- LOAD TEST STARTING ---")
print(f"Nodes: {NUM_NODES}")
print(f"Duration: {DURATION_SEC}s")
print(f"Target URL: {GATEWAY_URL}/ingest")

def simulate_node(node_idx):
    node_id = f"load-test-node-{node_idx}"
    start_time = time.time()
    req_count = 0
    err_count = 0
    limited_count = 0
    
    url = f"{GATEWAY_URL}/ingest"
    headers = {'Authorization': f'Bearer {TOKEN}', 'Content-Type': 'application/json'}
    
    while time.time() - start_time < DURATION_SEC:
        # Simulate full suite of metrics matching Agent
        mem_total = 16 * 1024 * 1024 * 1024 # 16 GB
        mem_used = random.uniform(0.1, 0.9) * mem_total

        payload = {
            "node_id": node_id,
            "timestamp": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
            "metrics": [
                {"name": "cpu_usage", "value": random.uniform(10, 90), "unit": "%"},
                {"name": "mem_used", "value": mem_used, "unit": "bytes"},
                {"name": "mem_total", "value": mem_total, "unit": "bytes"},
                {"name": "disk_percent", "value": random.uniform(20, 80), "unit": "%"},
                {"name": "process_count", "value": random.randint(50, 200), "unit": "count"},
                {"name": "net_bytes_recv", "value": random.uniform(1000, 1000000), "unit": "bytes"},
                {"name": "net_bytes_sent", "value": random.uniform(1000, 500000), "unit": "bytes"}
            ]
        }
        try:
            resp = requests.post(url, headers=headers, json=payload, timeout=2)
            if resp.status_code == 200:
                pass
            elif resp.status_code == 429:
                limited_count += 1
            else:
                err_count += 1
                # print(f"Node {node_idx} Error: {resp.status_code}")
        except Exception as e:
            err_count += 1
            # print(f"Node {node_idx} Exception: {e}")
        
        req_count += 1
        time.sleep(INTERVAL)
        
    return req_count, err_count, limited_count

# Run threads
with concurrent.futures.ThreadPoolExecutor(max_workers=NUM_NODES) as executor:
    futures = [executor.submit(simulate_node, i) for i in range(NUM_NODES)]
    
    total_req = 0
    total_err = 0
    total_limited = 0
    for f in concurrent.futures.as_completed(futures):
        r, e, l = f.result()
        total_req += r
        total_err += e
        total_limited += l

print(f"--- LOAD TEST FINISHED ---")
print(f"Total Requests: {total_req}")
print(f"Total Success: {total_req - total_err - total_limited}")
print(f"Total Rate Limited (429): {total_limited}")
print(f"Total Errors: {total_err}")

if total_err > (total_req * 0.05): # Fail if > 5% ACTUAL errors (500, timeouts)
    print("FAIL: Too many errors.")
    sys.exit(1)
elif total_req == 0:
    print("FAIL: No requests sent.")
    sys.exit(1)
else:
    print("SUCCESS: Infrastructure held up (Rate Limiting active).")
    sys.exit(0)
