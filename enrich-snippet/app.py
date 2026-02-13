"""
Container App — Custom Web API Skill for Azure AI Search.

For PDF documents that provide a pageNumber input, prepends "[Page X] "
to the snippet text so the page reference is visible in the KB MCP output.

For other document types (DOCX, etc.) the content is passed through
unchanged because page numbers are not available.

Input  (per record): { "content": "..." }            — DOCX (pass-through)
                      { "content": "...", "pageNumber": 3 }  — PDF  (prefixed)
Output (per record): { "enriched_snippet": "..." }

Deployed as an Azure Container App, called by the search indexer
skillset pipeline via WebApiSkill.
"""

from __future__ import annotations

import logging

from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("enrich-snippet")

app = FastAPI(title="enrich-snippet", docs_url=None, redoc_url=None)


@app.get("/health")
async def health():
    """Liveness / readiness probe."""
    return {"status": "ok"}


@app.post("/api/enrich_snippet")
async def enrich_snippet(request: Request):
    """Custom Web API Skill: prepend [Section X] or [Page X] to snippet."""
    try:
        body = await request.json()
    except Exception:
        logger.error("Invalid JSON body received")
        return JSONResponse(
            status_code=400,
            content={"values": [], "errors": [{"message": "Invalid JSON body"}]},
        )

    logger.info("Received %d records", len(body.get("values", [])))

    results = []
    for record in body.get("values", []):
        record_id = record.get("recordId", "0")
        data = record.get("data", {})

        # Accept content from multiple possible keys
        content = data.get("content", "") or ""

        # Try multiple paths for page number (populated for PDFs)
        page_number = data.get("pageNumber")
        if page_number is None:
            loc = data.get("locationMetadata") or {}
            page_number = loc.get("pageNumberFrom")

        if page_number is not None:
            # PDF with real page numbers
            enriched = f"[Page {page_number}] {content}"
        else:
            # DOCX / other: no reliable page info, pass through
            enriched = content

        logger.info(
            "rid=%s prefix=%s",
            record_id,
            enriched[:15],
        )

        results.append(
            {
                "recordId": record_id,
                "data": {"enriched_snippet": enriched},
                "errors": None,
                "warnings": None,
            }
        )

    logger.info("Returning %d results", len(results))
    return JSONResponse(content={"values": results})
