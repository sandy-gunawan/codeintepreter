"""
Sandbox Executor — runs inside a Kata-isolated pod.

Workflow:
  1. Read configuration from environment variables
  2. Download input data file from Azure Blob Storage (using SAS token)
  3. Execute the provided Python code
  4. Capture stdout, stderr, and generated output files
  5. Upload results back to Azure Blob Storage
  6. Write a JSON result manifest
"""

import io
import json
import os
import sys
import traceback
import glob
from contextlib import redirect_stdout, redirect_stderr
from datetime import datetime, timezone

from azure.storage.blob import BlobServiceClient


def download_input_data(blob_service_client: BlobServiceClient, container: str, blob_name: str, local_path: str):
    """Download input data from Azure Blob Storage."""
    blob_client = blob_service_client.get_blob_client(container=container, blob=blob_name)
    with open(local_path, "wb") as f:
        stream = blob_client.download_blob()
        f.write(stream.readall())
    print(f"[executor] Downloaded: {container}/{blob_name} -> {local_path}")


def upload_file(blob_service_client: BlobServiceClient, container: str, blob_name: str, local_path: str):
    """Upload a file to Azure Blob Storage."""
    blob_client = blob_service_client.get_blob_client(container=container, blob=blob_name)
    with open(local_path, "rb") as f:
        blob_client.upload_blob(f, overwrite=True)
    print(f"[executor] Uploaded: {local_path} -> {container}/{blob_name}")


def execute_code(code: str, data_path: str) -> dict:
    """Execute Python code in a restricted context and capture output."""
    stdout_capture = io.StringIO()
    stderr_capture = io.StringIO()

    # Prepare execution globals with data_path available
    exec_globals = {
        "__builtins__": __builtins__,
        "DATA_PATH": data_path,
        "OUTPUT_DIR": "/sandbox/outputs",
    }

    os.makedirs("/sandbox/outputs", exist_ok=True)

    start_time = datetime.now(timezone.utc)
    success = True
    error_message = None

    try:
        with redirect_stdout(stdout_capture), redirect_stderr(stderr_capture):
            exec(code, exec_globals)  # noqa: S102 — intentional exec in sandboxed environment
    except Exception:
        success = False
        error_message = traceback.format_exc()
        stderr_capture.write(error_message)

    end_time = datetime.now(timezone.utc)

    return {
        "success": success,
        "stdout": stdout_capture.getvalue(),
        "stderr": stderr_capture.getvalue(),
        "error": error_message,
        "start_time": start_time.isoformat(),
        "end_time": end_time.isoformat(),
        "duration_seconds": (end_time - start_time).total_seconds(),
    }


def main():
    # Configuration from environment variables
    # SAS URLs — container-level SAS tokens for datasets (read) and outputs (write)
    input_sas_url = os.environ.get("AZURE_STORAGE_SAS_URL", "")
    output_sas_url = os.environ.get("OUTPUT_SAS_URL", "")
    # Legacy support
    storage_conn_str = os.environ.get("AZURE_STORAGE_CONNECTION_STRING", "")

    input_container = os.environ.get("INPUT_CONTAINER", "datasets")
    input_blob = os.environ.get("INPUT_BLOB", "")
    output_container = os.environ.get("OUTPUT_CONTAINER", "outputs")
    execution_id = os.environ.get("EXECUTION_ID", "unknown")
    code_b64 = os.environ.get("CODE_BASE64", "")
    code_plain = os.environ.get("CODE", "")

    # Decode code
    if code_b64:
        import base64
        code = base64.b64decode(code_b64).decode("utf-8")
    elif code_plain:
        code = code_plain
    else:
        print("[executor] ERROR: No code provided (set CODE_BASE64 or CODE env var)")
        sys.exit(1)

    if not input_blob:
        print("[executor] ERROR: INPUT_BLOB env var not set")
        sys.exit(1)

    # Initialize blob clients
    # Use container-level SAS URLs (preferred) or connection string (legacy)
    if input_sas_url:
        from azure.storage.blob import ContainerClient
        input_client = ContainerClient.from_container_url(input_sas_url)
        output_client = ContainerClient.from_container_url(output_sas_url) if output_sas_url else None
        blob_service_client = None
        print(f"[executor] Using container SAS URLs")
    elif storage_conn_str:
        blob_service_client = BlobServiceClient.from_connection_string(storage_conn_str)
        input_client = None
        output_client = None
    else:
        print("[executor] ERROR: No storage credentials provided")
        sys.exit(1)

    # Step 1: Download input data
    input_ext = os.path.splitext(input_blob)[1]
    local_input = f"/sandbox/input_data{input_ext}"
    try:
        if input_client:
            # Container-level SAS — download from container client
            blob = input_client.get_blob_client(input_blob)
            with open(local_input, "wb") as f:
                f.write(blob.download_blob().readall())
            print(f"[executor] Downloaded: {input_blob} -> {local_input}")
        else:
            download_input_data(blob_service_client, input_container, input_blob, local_input)
    except Exception as e:
        print(f"[executor] ERROR downloading input: {e}")
        sys.exit(1)

    # Step 2: Execute code
    print(f"[executor] Executing code for execution_id={execution_id}")
    result = execute_code(code, local_input)

    # Step 3: Collect output files
    output_files = glob.glob("/sandbox/outputs/*")
    uploaded_outputs = []

    for output_file in output_files:
        filename = os.path.basename(output_file)
        blob_path = f"{execution_id}/{filename}"
        try:
            if output_client:
                blob = output_client.get_blob_client(blob_path)
                with open(output_file, "rb") as f:
                    blob.upload_blob(f, overwrite=True)
                print(f"[executor] Uploaded: {output_file} -> {blob_path}")
            else:
                upload_file(blob_service_client, output_container, blob_path, output_file)
            uploaded_outputs.append(blob_path)
        except Exception as e:
            print(f"[executor] WARNING: Failed to upload {filename}: {e}")

    # Step 4: Create and upload result manifest
    manifest = {
        "execution_id": execution_id,
        "success": result["success"],
        "stdout": result["stdout"],
        "stderr": result["stderr"],
        "error": result["error"],
        "start_time": result["start_time"],
        "end_time": result["end_time"],
        "duration_seconds": result["duration_seconds"],
        "output_files": uploaded_outputs,
    }

    manifest_json = json.dumps(manifest, indent=2)

    # Upload manifest
    manifest_blob = f"{execution_id}/manifest.json"
    try:
        if output_client:
            blob = output_client.get_blob_client(manifest_blob)
            blob.upload_blob(manifest_json, overwrite=True)
        else:
            blob_client = blob_service_client.get_blob_client(
                container=output_container, blob=manifest_blob
            )
            blob_client.upload_blob(manifest_json, overwrite=True)
        print(f"[executor] Manifest uploaded: {manifest_blob}")
    except Exception as e:
        print(f"[executor] WARNING: Failed to upload manifest: {e}")

    # Print manifest to stdout for orchestrator to capture from pod logs
    print("---MANIFEST_START---")
    print(manifest_json)
    print("---MANIFEST_END---")

    if not result["success"]:
        sys.exit(1)


if __name__ == "__main__":
    main()
