import os
import time
import datetime
import psycopg2
import logging

# Configuration
DB_HOST = os.getenv("DB_HOST", "timescaledb")
DB_USER = os.getenv("DB_USER", "nodesense")
DB_PASS = os.getenv("DB_PASS", "nodesensepass")
DB_NAME = os.getenv("DB_NAME", "nodesense")
CHECK_INTERVAL = int(os.getenv("CHECK_INTERVAL", "60"))

logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')

def check_metrics():
    conn = None
    try:
        conn = psycopg2.connect(
            host=DB_HOST,
            user=DB_USER,
            password=DB_PASS,
            database=DB_NAME
        )
        cur = conn.cursor()
        
        # Example: Check for high CPU usage (> 90%) in the last minute
        # Assuming table 'metrics' with columns: time, metric, value, node_id
        # Note: Adjust table/column names based on actual schema if known. 
        # Based on previous phases, we assume a simple schema.
        
        query = """
        SELECT time, node_id, value 
        FROM metrics 
        WHERE metric_name = 'cpu_usage' 
          AND value > 90.0 
          AND time > NOW() - INTERVAL '1 minute';
        """
        
        cur.execute(query)
        rows = cur.fetchall()
        
        if rows:
            for row in rows:
                msg = f"High CPU usage detected! Node: {row[1]}, Value: {row[2]}"
                logging.warning(f"ALERT: {msg}, Time: {row[0]}")
                # Persist to DB
                cur.execute("INSERT INTO alerts (node_id, message, timestamp) VALUES (%s, %s, %s)", (row[1], msg, row[0]))
                conn.commit()
        
        # Check for Node Down (No report in last 2 minutes)
        cur.execute("""
            SELECT id, last_seen 
            FROM nodes 
            WHERE last_seen < NOW() - INTERVAL '2 minutes';
        """)
        down_nodes = cur.fetchall()
        for node in down_nodes:
            msg = f"Node Down detected! Node: {node[0]}"
            logging.warning(f"ALERT: {msg}, Last Seen: {node[1]}")
            # Persist to DB
            cur.execute("INSERT INTO alerts (node_id, message, timestamp) VALUES (%s, %s, %s)", (node[0], msg, datetime.datetime.now(datetime.timezone.utc)))
            conn.commit()

        if not rows and not down_nodes:
            logging.info("No anomalies detected.")
            
        cur.close()
        
    except Exception as e:
        logging.error(f"Error checking metrics: {e}")
    finally:
        if conn:
            conn.close()

if __name__ == "__main__":
    logging.info("Starting Alerting Service...")
    # Give DB some time to come up
    time.sleep(5) 
    
    while True:
        check_metrics()
        time.sleep(CHECK_INTERVAL)
