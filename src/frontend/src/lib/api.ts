// In production, API_URL is empty string = same-origin relative URLs (Ingress routes /api to backend).
// For local dev, create .env.local with NEXT_PUBLIC_API_URL=http://localhost:8000
const API_URL = process.env.NEXT_PUBLIC_API_URL || '';

export interface UploadResponse {
  session_id: string;
  filename: string;
  blob_path: string;
  size_bytes: number;
}

export interface OutputFile {
  path: string;
  url: string;
  type: string;
}

export interface ChatResponse {
  execution_id: string;
  status: string;
  message: string;
  code: string | null;
  explanation: string | null;
  output_files: OutputFile[];
}

export async function uploadFile(file: File, sessionId?: string): Promise<UploadResponse> {
  const formData = new FormData();
  formData.append('file', file);
  if (sessionId) {
    formData.append('session_id', sessionId);
  }

  let url = `${API_URL}/api/upload`;
  if (sessionId) {
    url += `?session_id=${encodeURIComponent(sessionId)}`;
  }

  const res = await fetch(url, {
    method: 'POST',
    body: formData,
  });

  if (!res.ok) {
    const err = await res.json().catch(() => ({ detail: res.statusText }));
    throw new Error(err.detail || 'Upload failed');
  }

  return res.json();
}

export async function sendChat(
  prompt: string,
  datasetBlob: string,
  sessionId: string
): Promise<ChatResponse> {
  const res = await fetch(`${API_URL}/api/chat`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      prompt,
      dataset_blob: datasetBlob,
      session_id: sessionId,
    }),
  });

  if (!res.ok) {
    const err = await res.json().catch(() => ({ detail: res.statusText }));
    throw new Error(err.detail || 'Chat request failed');
  }

  return res.json();
}

export async function healthCheck(): Promise<boolean> {
  try {
    const res = await fetch(`${API_URL}/api/health`);
    return res.ok;
  } catch {
    return false;
  }
}
