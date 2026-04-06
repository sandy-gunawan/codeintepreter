"""File upload route."""

import uuid

from fastapi import APIRouter, UploadFile, File, HTTPException

from app.storage import storage_service

router = APIRouter()

ALLOWED_EXTENSIONS = {".csv", ".xlsx", ".xls"}
MAX_FILE_SIZE = 50 * 1024 * 1024  # 50 MB


@router.post("/upload")
async def upload_file(file: UploadFile = File(...), session_id: str | None = None):
    """Upload a dataset file (CSV or XLSX)."""
    if not file.filename:
        raise HTTPException(status_code=400, detail="No filename provided")

    ext = "." + file.filename.rsplit(".", 1)[-1].lower() if "." in file.filename else ""
    if ext not in ALLOWED_EXTENSIONS:
        raise HTTPException(
            status_code=400,
            detail=f"File type not allowed. Accepted: {', '.join(ALLOWED_EXTENSIONS)}",
        )

    if not session_id:
        session_id = str(uuid.uuid4())

    content = await file.read()
    if len(content) > MAX_FILE_SIZE:
        raise HTTPException(status_code=400, detail="File too large (max 50 MB)")

    blob_path = storage_service.upload_dataset(file.filename, content, session_id)

    return {
        "session_id": session_id,
        "filename": file.filename,
        "blob_path": blob_path,
        "size_bytes": len(content),
    }
