"""Sift parse service.

One endpoint. The iOS app posts a raw transcript plus its local clock; it gets back
structured items to show in the review sheet. Nothing is stored here — the phone owns
the data.
"""

import logging
from datetime import datetime

import anthropic
from dotenv import load_dotenv
from fastapi import FastAPI, HTTPException

from .parser import MissingCredentials, RefusalError, parse_capture
from .schema import ParseRequest, ParseResponse

# Picks up ANTHROPIC_API_KEY from server/.env during local development.
load_dotenv()

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
log = logging.getLogger("sift")

app = FastAPI(title="Sift", version="0.1.0")


@app.get("/health")
def health() -> dict:
    return {"ok": True}


@app.post("/parse", response_model=ParseResponse)
def parse(req: ParseRequest) -> ParseResponse:
    transcript = req.transcript.strip()
    if not transcript:
        raise HTTPException(status_code=400, detail="Empty transcript.")
    if len(transcript) > 8000:
        raise HTTPException(status_code=400, detail="Capture too long.")

    try:
        now = datetime.fromisoformat(req.now_local)
    except ValueError:
        raise HTTPException(status_code=400, detail="now_local must be ISO 8601.")

    try:
        result = parse_capture(transcript, now)
    except MissingCredentials as exc:
        raise HTTPException(status_code=503, detail=str(exc))
    except RefusalError as exc:
        raise HTTPException(status_code=422, detail=str(exc))
    except anthropic.RateLimitError:
        raise HTTPException(status_code=429, detail="Rate limited, try again shortly.")
    except anthropic.APIStatusError as exc:
        log.exception("upstream error")
        raise HTTPException(status_code=502, detail=f"Upstream error ({exc.status_code}).")
    except anthropic.APIConnectionError:
        log.exception("connection error")
        raise HTTPException(status_code=503, detail="Could not reach the model.")

    return ParseResponse(items=result.items, transcript=transcript)
