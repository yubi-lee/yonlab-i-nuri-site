import hashlib
import uuid
from enum import StrEnum

from fastapi import FastAPI, HTTPException
from pydantic import BaseModel, Field


class DataClass(StrEnum):
    PUBLIC = "public"
    INTERNAL = "internal"
    RESTRICTED = "restricted"


class Safeguarding(StrEnum):
    STANDARD = "standard"
    ELEVATED = "elevated"


class GatewayRequest(BaseModel):
    request_id: str = Field(min_length=1, max_length=120)
    data_class: DataClass
    safeguarding: Safeguarding = Safeguarding.STANDARD
    purpose: str = Field(min_length=2, max_length=120)
    prompt: str = Field(min_length=1, max_length=20_000)
    route: str = Field(default="deterministic-local", min_length=1, max_length=80)


class GatewayResponse(BaseModel):
    request_id: str
    provider: str
    model: str
    output_hash: str
    output: str
    raw_prompt_persisted: bool = False


app = FastAPI(title="YOnLearn AI Gateway", version="0.1.0")


@app.get("/health/live")
def live():
    return {"status": "ok"}


@app.post("/v1/generate", response_model=GatewayResponse)
def generate(data: GatewayRequest):
    if data.route != "deterministic-local" and data.data_class == DataClass.RESTRICTED:
        raise HTTPException(status_code=403, detail="Restricted data requires a local approved route")
    if data.safeguarding == Safeguarding.ELEVATED and data.route != "deterministic-local":
        raise HTTPException(status_code=403, detail="Elevated safeguarding requires the local route")
    digest = hashlib.sha256(data.prompt.encode("utf-8")).hexdigest()
    return {
        "request_id": data.request_id,
        "provider": "deterministic-local",
        "model": "gateway-policy.v1",
        "output_hash": digest,
        "output": f"Deterministic response {uuid.uuid5(uuid.NAMESPACE_URL, digest)}",
        "raw_prompt_persisted": False,
    }
