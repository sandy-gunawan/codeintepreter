"""Storage service — Azure Blob Storage operations."""

import json
from datetime import datetime, timezone, timedelta

from azure.identity import DefaultAzureCredential
from azure.storage.blob import (
    BlobServiceClient,
    generate_blob_sas,
    BlobSasPermissions,
    UserDelegationKey,
)

from app.config import settings


class StorageService:
    def __init__(self):
        self._client = None
        self._credential = None
        self.datasets_container = settings.storage_datasets_container
        self.outputs_container = settings.storage_outputs_container
        self.audit_container = settings.storage_audit_container

    @property
    def credential(self):
        if self._credential is None:
            self._credential = DefaultAzureCredential()
        return self._credential

    @property
    def client(self) -> BlobServiceClient:
        if self._client is None:
            account_url = f"https://{settings.azure_storage_account_name}.blob.core.windows.net"
            self._client = BlobServiceClient(account_url, credential=self.credential)
        return self._client

    def upload_dataset(self, filename: str, data: bytes, session_id: str) -> str:
        """Upload a dataset file and return the blob path."""
        blob_path = f"{session_id}/{filename}"
        blob_client = self.client.get_blob_client(
            container=self.datasets_container, blob=blob_path
        )
        blob_client.upload_blob(data, overwrite=True)
        return blob_path

    def get_data_preview(self, blob_path: str, max_rows: int = 10) -> str:
        """Download and return a preview of a dataset."""
        blob_client = self.client.get_blob_client(
            container=self.datasets_container, blob=blob_path
        )
        content = blob_client.download_blob().readall().decode("utf-8")
        lines = content.strip().split("\n")
        preview_lines = lines[: max_rows + 1]  # header + rows
        return "\n".join(preview_lines)

    def get_execution_manifest(self, execution_id: str) -> dict | None:
        """Download the execution result manifest."""
        blob_path = f"{execution_id}/manifest.json"
        blob_client = self.client.get_blob_client(
            container=self.outputs_container, blob=blob_path
        )
        try:
            content = blob_client.download_blob().readall().decode("utf-8")
            return json.loads(content)
        except Exception:
            return None

    def get_output_file_url(self, blob_path: str) -> str:
        """Get a user-delegation SAS URL for an output file (no account key needed)."""
        delegation_key = self.client.get_user_delegation_key(
            key_start_time=datetime.now(timezone.utc),
            key_expiry_time=datetime.now(timezone.utc) + timedelta(hours=1),
        )
        sas_token = generate_blob_sas(
            account_name=settings.azure_storage_account_name,
            container_name=self.outputs_container,
            blob_name=blob_path,
            user_delegation_key=delegation_key,
            permission=BlobSasPermissions(read=True),
            expiry=datetime.now(timezone.utc) + timedelta(hours=1),
        )
        blob_client = self.client.get_blob_client(
            container=self.outputs_container, blob=blob_path
        )
        return f"{blob_client.url}?{sas_token}"

    def generate_sandbox_sas(self) -> str:
        """Generate a user-delegation SAS URL for sandbox pods (read datasets, write outputs)."""
        from azure.storage.blob import ContainerSasPermissions, generate_container_sas

        delegation_key = self.client.get_user_delegation_key(
            key_start_time=datetime.now(timezone.utc) - timedelta(minutes=5),
            key_expiry_time=datetime.now(timezone.utc) + timedelta(minutes=30),
        )
        expiry = datetime.now(timezone.utc) + timedelta(minutes=30)

        # SAS for datasets container (read)
        self._datasets_sas = generate_container_sas(
            account_name=settings.azure_storage_account_name,
            container_name=self.datasets_container,
            user_delegation_key=delegation_key,
            permission=ContainerSasPermissions(read=True, list=True),
            expiry=expiry,
        )
        # SAS for outputs container (read + write + create)
        self._outputs_sas = generate_container_sas(
            account_name=settings.azure_storage_account_name,
            container_name=self.outputs_container,
            user_delegation_key=delegation_key,
            permission=ContainerSasPermissions(read=True, write=True, create=True),
            expiry=expiry,
        )
        # Return the account URL — executor appends container-specific SAS
        return f"https://{settings.azure_storage_account_name}.blob.core.windows.net"

    def get_sandbox_sas_tokens(self) -> dict:
        """Get separate SAS tokens for datasets and outputs containers."""
        self.generate_sandbox_sas()
        return {
            "datasets": self._datasets_sas,
            "outputs": self._outputs_sas,
        }

    def write_audit_log(self, entry: dict):
        """Write an audit log entry to blob storage."""
        timestamp = datetime.now(timezone.utc).strftime("%Y/%m/%d/%H")
        blob_path = f"{timestamp}/{entry.get('execution_id', 'unknown')}.json"
        blob_client = self.client.get_blob_client(
            container=self.audit_container, blob=blob_path
        )
        blob_client.upload_blob(
            json.dumps(entry, indent=2, default=str), overwrite=True
        )


storage_service = StorageService()
