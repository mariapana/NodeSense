from fastapi import FastAPI, HTTPException
from models import IngestPayload
import asyncio
from db import get_pool, upsert_node, insert_metrics
from prometheus_client import make_asgi_app, Gauge

app = FastAPI()

# Prometheus Metrics
metrics_app = make_asgi_app()
app.mount("/metrics", metrics_app)

NODE_METRIC = Gauge("node_metric", "Metric value from node", ["node_id", "name", "unit"])
NODE_LAST_SEEN = Gauge("node_last_seen", "Last seen timestamp of the node", ["node_id"])


@app.get("/health")
async def health():
    return {"status": "ok"}


@app.post("/ingest")
async def ingest(payload: IngestPayload):
    # Update Prometheus metrics
    NODE_LAST_SEEN.labels(node_id=payload.node_id).set_to_current_time()
    
    for m in payload.metrics:
        NODE_METRIC.labels(
            node_id=payload.node_id, 
            name=m.name, 
            unit=m.unit or ""
        ).set(m.value)

    try:
        pool = await get_pool()
        async with pool.acquire() as conn:
            async with conn.transaction():
                await upsert_node(conn, payload.node_id)
                await insert_metrics(
                    conn, payload.node_id, payload.timestamp, payload.metrics
                )

        return {"status": "ok"}
    except Exception as e:
        print("Collector error:", e)
        raise HTTPException(status_code=500, detail=str(e))
