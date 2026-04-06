"""Chat route — handles user prompts and orchestrates analysis."""

from pydantic import BaseModel
from fastapi import APIRouter, HTTPException

from app.orchestrator import process_chat

router = APIRouter()


class ChatRequest(BaseModel):
    prompt: str
    dataset_blob: str
    session_id: str


class OutputFile(BaseModel):
    path: str
    url: str
    type: str


class ChatResponse(BaseModel):
    execution_id: str
    status: str
    message: str
    code: str | None = None
    explanation: str | None = None
    output_files: list[OutputFile] = []


@router.post("/chat", response_model=ChatResponse)
async def chat(request: ChatRequest):
    """Process a user prompt against an uploaded dataset."""
    if not request.prompt.strip():
        raise HTTPException(status_code=400, detail="Prompt cannot be empty")
    if not request.dataset_blob.strip():
        raise HTTPException(status_code=400, detail="dataset_blob is required")

    result = await process_chat(
        user_prompt=request.prompt,
        dataset_blob=request.dataset_blob,
        session_id=request.session_id,
    )

    return ChatResponse(**result)
