import os
import time
import httpx
import redis.asyncio as redis
import docker
from fastapi import FastAPI, Request, Response, HTTPException, Security
from fastapi.middleware.cors import CORSMiddleware
from auth import verify_token, verify_admin
from pydantic import BaseModel, Field
from typing import List
from datetime import datetime

class Metric(BaseModel):
    name: str
    value: float
    unit: str | None = None

class IngestPayload(BaseModel):
    node_id: str = Field(..., min_length=1)
    timestamp: datetime
    metrics: List[Metric]

app = FastAPI(title="NodeSense Gateway")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Configuration
REDIS_URL = os.getenv("REDIS_URL", "redis://redis:6379")
COLLECTOR_URL = os.getenv("COLLECTOR_URL", "http://collector:3000")
RATE_LIMIT_WINDOW = 60  # seconds
RATE_LIMIT_MAX_REQUESTS = int(os.getenv("RATE_LIMIT", "1000"))  # requests per window

# Redis Connection
r = redis.from_url(REDIS_URL, encoding="utf-8", decode_responses=True)

# Docker Client
try:
    docker_client = docker.from_env()
except Exception as e:
    print(f"Warning: Docker client failed to initialize: {e}")
    docker_client = None

async def check_rate_limit(client_id: str):
    key = f"rate_limit:{client_id}"
    current = await r.incr(key)
    if current == 1:
        await r.expire(key, RATE_LIMIT_WINDOW)
    if current > RATE_LIMIT_MAX_REQUESTS:
        return False
    return True

print("DEBUG: App Module Loaded")

@app.middleware("http")
async def add_server_header(request: Request, call_next):
    response = await call_next(request)
    response.headers["X-Served-By"] = os.getenv("HOSTNAME", "unknown")
    return response

@app.middleware("http")
async def rate_limit_middleware(request: Request, call_next):
    client_ip = request.client.host
    if "x-forwarded-for" in request.headers:
        client_ip = request.headers["x-forwarded-for"]
    
    if not await check_rate_limit(client_ip):
        return Response(content='{"detail": "Rate limit exceeded"}', status_code=429, media_type="application/json")
    
    response = await call_next(request)
    return response

@app.get("/health")
async def health_check():
    return {"status": "ok", "service": "gateway", "host": os.getenv("HOSTNAME", "unknown")}

@app.post("/api/debug/db-error")
async def debug_db_error_proxy(user=Security(verify_token)):
    # Proxy to collector debug endpoint
    try:
        rp_resp = await client.post("/debug/db-error")
        return Response(content=rp_resp.content, status_code=rp_resp.status_code)
    except httpx.ConnectError:
         raise HTTPException(status_code=503, detail="Collector service unavailable")

@app.get("/ping")
async def ping():
    return "pong"

# Reverse Proxy Client
client = httpx.AsyncClient(base_url=COLLECTOR_URL)

class LoginRequest(BaseModel):
    username: str
    password: str
    client_secret: str

@app.post("/api/login")
async def login_proxy(creds: LoginRequest):
    kc_url = os.getenv("KEYCLOAK_URL", "http://keycloak:8080")
    token_url = f"{kc_url}/realms/NodeSense/protocol/openid-connect/token"
    
    data = {
        "grant_type": "password",
        "username": creds.username,
        "password": creds.password,
        "client_id": "api-gateway",
        "client_secret": creds.client_secret
    }
    
    try:
        async with httpx.AsyncClient() as kc_client:
            resp = await kc_client.post(token_url, data=data)
            return Response(content=resp.content, status_code=resp.status_code, media_type="application/json")
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/api/nodes")
async def get_nodes_proxy():
    try:
        rp_resp = await client.get("/nodes")
        return Response(content=rp_resp.content, status_code=rp_resp.status_code, headers=rp_resp.headers)
    except httpx.ConnectError:
         raise HTTPException(status_code=503, detail="Collector service unavailable")

@app.delete("/api/nodes/{node_id}")
async def delete_node_proxy(node_id: str, user=Security(verify_admin)):
    try:
        rp_resp = await client.delete(f"/nodes/{node_id}")
        return Response(content=rp_resp.content, status_code=rp_resp.status_code)
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.delete("/api/nodes")
async def delete_all_nodes_proxy(user=Security(verify_admin)):
    try:
        rp_resp = await client.delete("/nodes")
        return Response(content=rp_resp.content, status_code=rp_resp.status_code)
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/api/system/topology")
async def get_system_topology(user=Security(verify_admin)):
    if not docker_client:
        raise HTTPException(status_code=503, detail="Docker socket not available")
    
    try:
        services = docker_client.services.list()
        topology = []
        for svc in services:
            name = svc.name
            # Simply get replicas count
            replicas = 0
            mode = svc.attrs.get("Spec", {}).get("Mode", {})
            if "Replicated" in mode:
                replicas = mode.get("Replicated", {}).get("Replicas", 1)
            elif "Global" in mode:
                # Global mode runs on all nodes, hard to report a single "replica" number without checking nodes
                # For demo, we'll mark it as 'Global' or -1
                replicas = -1 
            
            topology.append({
                "id": svc.id,
                "name": name,
                "replicas": replicas,
                "image": svc.attrs.get("Spec", {}).get("TaskTemplate", {}).get("ContainerSpec", {}).get("Image", "")
            })
        return topology
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/api/system/logs/{service_name}")
async def get_service_logs(service_name: str, user=Security(verify_admin)):
    if not docker_client:
         raise HTTPException(status_code=503, detail="Docker socket not available")
    
    try:
        services = docker_client.services.list(filters={"name": service_name})
        if not services:
             raise HTTPException(status_code=404, detail="Service not found")
        
        # Use low-level API to avoid blocking generators
        service = services[0]
        print(f"DEBUG: Low-level logs fetch for {service.name}", flush=True)
        
        # Returns bytes if stream=False, generator if stream=True
        # We explicitly want headers/timestamps/stdout/stderr, strict blocking=False
        logs = docker_client.api.service_logs(
            service.id,
            stdout=True, 
            stderr=True, 
            tail=50, 
            timestamps=True,
            follow=False
        )
        # It might return a generator in some versions, force iter if so, else bytes
        decoded_logs = []
        
        if hasattr(logs, '__iter__') and not isinstance(logs, (bytes, str)):
             print("DEBUG: Low-level returned generator, draining...", flush=True)
             for line in logs:
                 decoded_logs.append(line.decode('utf-8', errors='replace').strip())
        else:
             print(f"DEBUG: Low-level returned bytes (len={len(logs)})", flush=True)
             decoded = logs.decode("utf-8", errors='replace')
             decoded_logs = decoded.split("\n")
        
        clean_logs = [l for l in decoded_logs if l.strip()]
        return {"service": service.name, "logs": clean_logs}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/api/system/alerts")
async def get_alerts(user=Security(verify_token)):
    # Read alerts from DB
    try:
        import asyncpg
        conn = await asyncpg.connect(
            user=os.getenv("DB_USER", "nodesense"),
            password=os.getenv("DB_PASS", "nodesensepass"),
            database=os.getenv("DB_NAME", "nodesense"),
            host=os.getenv("DB_HOST", "timescaledb")
        )
        rows = await conn.fetch("SELECT * FROM alerts ORDER BY timestamp DESC LIMIT 50")
        await conn.close()
        
        alerts = []
        for r in rows:
            alerts.append({
                "id": r["id"],
                "node_id": r["node_id"],
                "message": r["message"],
                "timestamp": r["timestamp"].isoformat() if r["timestamp"] else None,
                "read": r["read"]
            })
        return alerts
    except Exception as e:
        print(f"Alert fetch error: {e}")
        return [] # Return empty on error to not break UI

@app.post("/ingest")
async def ingest(payload: IngestPayload, user=Security(verify_token)):
    # Proxy ingest to collector
    try:
        rp_resp = await client.post("/ingest", json=payload.model_dump(mode='json'))
        return Response(content=rp_resp.content, status_code=rp_resp.status_code)
    except httpx.ConnectError:
         raise HTTPException(status_code=503, detail="Collector service unavailable")

@app.api_route("/{path_name:path}", methods=["GET", "POST", "PUT", "DELETE"])
async def proxy_to_collector(request: Request, path_name: str, user=Security(verify_token)):
    # Fallback generic proxy
    if not path_name.startswith("/"):
        path_name = "/" + path_name
    
    url = path_name
    if request.url.query:
        url += "?" + request.url.query
    
    rp_req = client.build_request(
        request.method,
        url,
        headers=request.headers.raw,
        content=await request.body()
    )
    
    try:
        rp_resp = await client.send(rp_req)
        return Response(content=rp_resp.content, status_code=rp_resp.status_code, headers=rp_resp.headers)
    except httpx.ConnectError:
         raise HTTPException(status_code=503, detail="Collector service unavailable")
