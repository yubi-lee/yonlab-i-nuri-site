# YOnLearn AI Gateway

This service is the provider-neutral boundary for AI workloads. The backend may
request deterministic local inference through this API, but it must not carry
provider SDKs, provider credentials, or routing policy.

## Local run

```powershell
python -m uvicorn app.main:app --app-dir services/ai-gateway --port 8010
```

The gateway rejects restricted data on external routes and never returns raw
prompt content. Provider adapters are intentionally separate from this first
deterministic implementation.
