import asyncpg
import os

DB_HOST = os.getenv("DB_HOST", "timescaledb")
DB_NAME = os.getenv("DB_NAME", "nodesense")
DB_USER = os.getenv("DB_USER", "nodesense")
DB_PASS = os.getenv("DB_PASS", "nodesensepass")

_pool = None


async def get_pool():
    global _pool

    if _pool is None:
        _pool = await asyncpg.create_pool(
            host=DB_HOST,
            database=DB_NAME,
            user=DB_USER,
            password=DB_PASS,
            min_size=1,
            max_size=10,
        )
    return _pool


async def upsert_node(conn, node_id: str):
    await conn.execute(
        """
        INSERT INTO nodes (id, name)
        VALUES ($1, $1)
        ON CONFLICT (id) DO UPDATE
            SET last_seen = now()
        """,
        node_id,
    )


async def insert_metrics(conn, node_id: str, timestamp, metrics):
    rows = [(timestamp, node_id, m.name, m.value, m.unit) for m in metrics]

    await conn.executemany(
        """
        INSERT INTO metrics (time, node_id, metric_name, value, unit)
        VALUES ($1, $2, $3, $4, $5)
        """,
        rows,
    )

async def get_all_nodes(conn):
    rows = await conn.fetch("SELECT id, name, last_seen FROM nodes ORDER BY last_seen DESC")
    return [{"id": r["id"], "name": r["name"], "last_seen": r["last_seen"]} for r in rows]


async def delete_node(conn, node_id: str):
    await conn.execute("DELETE FROM nodes WHERE id = $1", node_id)


async def delete_all_nodes(conn):
    await conn.execute("DELETE FROM nodes")

async def init_alerts_table(conn):
    await conn.execute("""
        CREATE TABLE IF NOT EXISTS alerts (
            id SERIAL PRIMARY KEY,
            node_id TEXT,
            message TEXT,
            timestamp TIMESTAMPTZ NOT NULL,
            read BOOLEAN DEFAULT FALSE
        );
    """)
