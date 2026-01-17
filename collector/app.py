from fastapi import FastAPI, HTTPException
from models import IngestPayload
import asyncio
from db import get_pool, upsert_node, insert_metrics, get_all_nodes, delete_node, delete_all_nodes, trigger_db_error
from prometheus_client import make_asgi_app, Gauge

app = FastAPI()

# Prometheus Metrics
metrics_app = make_asgi_app()
app.mount("/metrics", metrics_app)

NODE_METRIC = Gauge("node_metric", "Metric value from node", ["node_id", "name", "unit"])
NODE_LAST_SEEN = Gauge("node_last_seen", "Last seen timestamp of the node", ["node_id"])


@app.on_event("startup")
async def startup_event():
    try:
        from db import init_alerts_table
        pool = await get_pool()
        async with pool.acquire() as conn:
            await init_alerts_table(conn)
    except Exception as e:
        print(f"Startup DB init failed: {e}")

@app.get("/health")
async def health():
    return {"status": "ok"}


@app.get("/nodes")
async def get_nodes():
    try:
        pool = await get_pool()
        async with pool.acquire() as conn:
            nodes = await get_all_nodes(conn)
        return nodes
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.delete("/nodes/{node_id}")
async def delete_node_endpoint(node_id: str):
    try:
        pool = await get_pool()
        async with pool.acquire() as conn:
            deleted_count = await delete_node(conn, node_id)
        
        if deleted_count == 0:
            raise HTTPException(status_code=404, detail=f"Node {node_id} not found")

        return {"status": "deleted", "id": node_id}
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.delete("/nodes")
async def delete_all_nodes_endpoint():
    try:
        pool = await get_pool()
        async with pool.acquire() as conn:
            await delete_all_nodes(conn)
        return {"status": "all deleted"}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/debug/db-error")
async def debug_db_error():
    try:
        pool = await get_pool()
        async with pool.acquire() as conn:
            await trigger_db_error(conn)
        return {"status": "ok"}
    except Exception as e:
        # We want to return 500 but with the specific error message to prove it happened
        raise HTTPException(status_code=500, detail=str(e))


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
        raise HTTPException(status_code=500, detail=str(e))
