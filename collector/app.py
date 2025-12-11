from fastapi import FastAPI, HTTPException
from models import IngestPayload
import asyncio
from db import get_pool, upsert_node, insert_metrics

app = FastAPI()


@app.get("/health")
async def health():
    return {"status": "ok"}


@app.post("/ingest")
async def ingest(payload: IngestPayload):
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
