import urllib.request
import urllib.error
import time
from collections import Counter

url = "http://127.0.0.1:8000/health"
results = []

print(f"Testing Rate Limit on {url} with 110 requests...")

start_time = time.time()
for i in range(110):
    try:
        with urllib.request.urlopen(url) as response:
            results.append(response.getcode())
    except urllib.error.HTTPError as e:
        results.append(e.code)
    except Exception as e:
        results.append(str(e))
        
    if i % 10 == 0:
        print(f"Request {i+1}/110...", end="\r")

print(f"\nCompleted in {time.time() - start_time:.2f} seconds.")

counts = Counter(results)
print("\n=== Results ===")
for code, count in sorted(counts.items()):
    print(f"Status {code}: {count} requests")

if counts.get(429, 0) > 0:
    print("\nSUCCESS: Rate limiting acts correctly (429 responses received).")
else:
    print("\nFAILURE: No rate limiting detected.")
