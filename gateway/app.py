import os
import time
import httpx
import redis.asyncio as redis
from fastapi import FastAPI, Request, Response, HTTPException

app = FastAPI(title="NodeSense Gateway")

# Configuration
REDIS_URL = os.getenv("REDIS_URL", "redis://redis:6379")
COLLECTOR_URL = os.getenv("COLLECTOR_URL", "http://collector:3000")
RATE_LIMIT_WINDOW = 60  # seconds
RATE_LIMIT_MAX_REQUESTS = 100  # requests per window

# Redis Connection
r = redis.from_url(REDIS_URL, encoding="utf-8", decode_responses=True)

async def check_rate_limit(client_id: str):
    """
    Implements a simple fixed-window rate limiting algorithm using Redis.
    """
    key = f"rate_limit:{client_id}"
    current = await r.incr(key)
    
    if current == 1:
        await r.expire(key, RATE_LIMIT_WINDOW)
    
    if current > RATE_LIMIT_MAX_REQUESTS:
        return False
    return True

@app.middleware("http")
async def rate_limit_middleware(request: Request, call_next):
    # Identify client by IP or X-Forwarded-For
    client_ip = request.client.host
    if "x-forwarded-for" in request.headers:
        client_ip = request.headers["x-forwarded-for"]
    
    # Rate Limit Check
    is_allowed = await check_rate_limit(client_ip)
    if not is_allowed:
        return Response(content="Rate limit exceeded", status_code=429)
    
    response = await call_next(request)
    return response

@app.get("/health")
async def health_check():
    try:
        await r.ping()
        redis_status = "connected"
    except Exception as e:
        redis_status = f"error: {str(e)}"
    return {"status": "ok", "service": "gateway", "redis": redis_status}

# Reverse Proxy for Collector
client = httpx.AsyncClient(base_url=COLLECTOR_URL)

@app.api_route("/{path_name:path}", methods=["GET", "POST", "PUT", "DELETE"])
async def proxy_to_collector(request: Request, path_name: str):
    if not path_name.startswith("/"):
        path_name = "/" + path_name
    
    url = path_name
    if request.url.query:
        url += "?" + request.url.query
    
    # We only want to proxy specific routes or all? 
    # For Phase 3, we specifically care about /ingest and /metrics usually going through gateway?
    # Or maybe just /ingest. 
    # Let's proxy everything to collector for now, acting as a facade.
    
    rp_req = client.build_request(
        request.method,
        url,
        headers=request.headers.raw,
        content=await request.body()
    )
    
    try:
        rp_resp = await client.send(rp_req)
    except httpx.ConnectError:
         raise HTTPException(status_code=503, detail="Collector service unavailable")

    return Response(
        content=rp_resp.content,
        status_code=rp_resp.status_code,
        headers=rp_resp.headers
    )
