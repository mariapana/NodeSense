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
