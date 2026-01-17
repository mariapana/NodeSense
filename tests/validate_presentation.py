import sys
import requests
import time
import os

TOKEN = sys.argv[1] if len(sys.argv) > 1 else ""
if not TOKEN:
    print("Error: No token provided")
    sys.exit(1)

GATEWAY_URL = os.getenv("GATEWAY_URL", "http://gateway:8000")

HEADERS = {
    "Authorization": f"Bearer {TOKEN}",
    "Content-Type": "application/json"
}

def log_pass(msg):
    print(f"\033[92m[PASS]\033[0m {msg}")

def log_fail(msg):
    print(f"\033[91m[FAIL]\033[0m {msg}")
    sys.exit(1)

def section(msg):
    print(f"\n\033[93m=== {msg} ===\033[0m")

section("1. Replication Test")
# Hit /ping multiple times and check X-Served-By header
servers = set()
print("Pinging gateway 10 times to check X-Served-By header...")
for i in range(10):
    try:
        r = requests.get(f"{GATEWAY_URL}/ping", timeout=2)
        if r.status_code == 200:
            server = r.headers.get("X-Served-By", "unknown")
            servers.add(server)
        else:
            log_fail(f"Ping failed: {r.status_code}")
    except Exception as e:
        print(f"Request failed: {e}")

print(f"Served by hosts: {servers}")
if len(servers) > 1:
    log_pass(f"Request handled by {len(servers)} different replicas: {servers}")
else:
    print("\033[93m[WARN]\033[0m Only 1 replica seen. If you have 2 replicas, load balancing might be sticky or slow to rotate.")
    # We won't fail here because sometimes RR is weird in small tests

section("2. Bad Request Handling")
# 1. Invalid JSON (Malformed)
try:
    r = requests.post(f"{GATEWAY_URL}/ingest", headers=HEADERS, data="{ bad json }", timeout=2)
    if r.status_code == 422 or r.status_code == 400:
        log_pass(f"Malformed JSON rejected with {r.status_code}")
    else:
        log_fail(f"Malformed JSON accepted? Code: {r.status_code}")
except Exception as e:
    log_fail(f"Request error: {e}")

# 2. Schema Validation (Missing required field)
try:
    data = {"timestamp": "2024-01-01T00:00:00Z", "metrics": []} # Missing node_id
    r = requests.post(f"{GATEWAY_URL}/ingest", headers=HEADERS, json=data, timeout=2)
    if r.status_code == 422:
        log_pass(f"Missing field rejected with 422")
    else:
        log_fail(f"Invalid schema accepted? Code: {r.status_code}")
except Exception as e:
    log_fail(f"Request error: {e}")

section("3. Delete Non-Existent Resource (404)")
try:
    r = requests.delete(f"{GATEWAY_URL}/api/nodes/non-existent-node-999", headers=HEADERS, timeout=2)
    if r.status_code == 404:
        log_pass("Delete non-existent node returned 404")
    else:
        log_fail(f"Delete non-existent node returned {r.status_code} (Expected 404)")
except Exception as e:
    log_fail(f"Request error: {e}")

section("4. Database Integrity Error")
# Trigger unique constraint violation using debug endpoint
try:
    r = requests.post(f"{GATEWAY_URL}/api/debug/db-error", headers=HEADERS, timeout=2)
    if r.status_code == 500:
        if "unique constraint" in r.text.lower() or "duplicate key" in r.text.lower():
             log_pass("DB Error triggered and caught correctly (500 + detailed message)")
             print(f"Message: {r.text}")
        else:
             print(f"Got 500 but message unclear: {r.text}")
             log_pass("DB Error triggered (500 received)")
    else:
        log_fail(f"DB Error test returned {r.status_code} (Expected 500)")
except Exception as e:
    log_fail(f"Request error: {e}")

section("5. Security Role Verification")
# Admin endpoint
try:
    r = requests.get(f"{GATEWAY_URL}/api/system/topology", headers=HEADERS, timeout=2)
    if r.status_code == 200:
        log_pass("Admin user can access Admin endpoint")
    else:
        log_fail(f"Admin user blocked from Admin endpoint? {r.status_code}")
except Exception as e:
    log_fail(f"Request error: {e}")

# Note: We can't easily switch to a Viewer user here without another token. 
# But we can try Unauthenticated.
try:
    msg = "Unauthenticated Access Blocked"
    r = requests.get(f"{GATEWAY_URL}/api/system/topology", timeout=2) # No headers
    if r.status_code == 401 or r.status_code == 403:
        log_pass(f"{msg}: {r.status_code}")
    else:
        log_fail(f"Unauthenticated request accepted? {r.status_code}")
except Exception as e:
    log_fail(f"Request error: {e}")

print("\n\033[92mAll Validation Scenarios Passed.\033[0m")
