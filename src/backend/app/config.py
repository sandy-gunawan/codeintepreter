"""Configuration via environment variables."""

from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    # Azure OpenAI
    azure_openai_endpoint: str = ""
    azure_openai_key: str = ""
    azure_openai_deployment: str = "gpt-4.1"
    azure_openai_api_version: str = "2024-12-01-preview"

    # Azure Storage
    azure_storage_connection_string: str = ""
    azure_storage_account_name: str = ""
    azure_storage_account_key: str = ""
    storage_datasets_container: str = "datasets"
    storage_outputs_container: str = "outputs"
    storage_audit_container: str = "audit-logs"

    # Kubernetes / Sandbox
    sandbox_namespace: str = "sandbox"
    sandbox_image: str = ""
    sandbox_cpu_limit: str = "1"
    sandbox_memory_limit: str = "1Gi"
    sandbox_timeout_seconds: int = 300
    sandbox_node_pool: str = "sandboxpool"

    # ACR
    acr_login_server: str = ""

    # LLM Provider
    llm_provider: str = "azure"

    # Server
    cors_origins: str = "*"

    model_config = {"env_file": ".env", "case_sensitive": False}


settings = Settings()
