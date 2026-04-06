"""Sandbox service — creates and monitors Kubernetes Jobs for code execution."""

import base64
import json
import time
import uuid
import logging

from kubernetes import client, config
from kubernetes.client.rest import ApiException

from app.config import settings

logger = logging.getLogger(__name__)


class SandboxService:
    def __init__(self):
        self._initialized = False
        self.namespace = settings.sandbox_namespace

    def _ensure_initialized(self):
        if not self._initialized:
            try:
                config.load_incluster_config()
            except config.ConfigException:
                config.load_kube_config()
            self.batch_v1 = client.BatchV1Api()
            self.core_v1 = client.CoreV1Api()
            self._initialized = True

    def create_execution(
        self,
        code: str,
        input_blob: str,
        storage_account_url: str,
        sas_tokens: dict,
        execution_id: str | None = None,
    ) -> str:
        """Create a sandbox Job to execute code. Returns execution_id."""
        self._ensure_initialized()

        if not execution_id:
            execution_id = str(uuid.uuid4())

        code_b64 = base64.b64encode(code.encode("utf-8")).decode("utf-8")
        job_name = f"sandbox-{execution_id[:8]}"

        job = client.V1Job(
            api_version="batch/v1",
            kind="Job",
            metadata=client.V1ObjectMeta(
                name=job_name,
                namespace=self.namespace,
                labels={
                    "app": "sandbox-executor",
                    "execution-id": execution_id[:63],
                },
            ),
            spec=client.V1JobSpec(
                ttl_seconds_after_finished=300,
                active_deadline_seconds=settings.sandbox_timeout_seconds,
                backoff_limit=0,
                template=client.V1PodTemplateSpec(
                    metadata=client.V1ObjectMeta(
                        labels={
                            "app": "sandbox-executor",
                            "execution-id": execution_id[:63],
                        },
                    ),
                    spec=client.V1PodSpec(
                        runtime_class_name="kata-vm-isolation",
                        restart_policy="Never",
                        automount_service_account_token=False,
                        node_selector={"agentpool": settings.sandbox_node_pool},
                        tolerations=[
                            client.V1Toleration(
                                key="sandbox",
                                operator="Equal",
                                value="true",
                                effect="NoSchedule",
                            )
                        ],
                        containers=[
                            client.V1Container(
                                name="executor",
                                image=settings.sandbox_image,
                                resources=client.V1ResourceRequirements(
                                    requests={
                                        "cpu": "500m",
                                        "memory": "512Mi",
                                    },
                                    limits={
                                        "cpu": settings.sandbox_cpu_limit,
                                        "memory": settings.sandbox_memory_limit,
                                    },
                                ),
                                env=[
                                    client.V1EnvVar(
                                        name="AZURE_STORAGE_SAS_URL",
                                        value=f"{storage_account_url}/{settings.storage_datasets_container}?{sas_tokens['datasets']}",
                                    ),
                                    client.V1EnvVar(
                                        name="OUTPUT_SAS_URL",
                                        value=f"{storage_account_url}/{settings.storage_outputs_container}?{sas_tokens['outputs']}",
                                    ),
                                    client.V1EnvVar(
                                        name="INPUT_CONTAINER",
                                        value=settings.storage_datasets_container,
                                    ),
                                    client.V1EnvVar(
                                        name="INPUT_BLOB",
                                        value=input_blob,
                                    ),
                                    client.V1EnvVar(
                                        name="OUTPUT_CONTAINER",
                                        value=settings.storage_outputs_container,
                                    ),
                                    client.V1EnvVar(
                                        name="EXECUTION_ID",
                                        value=execution_id,
                                    ),
                                    client.V1EnvVar(
                                        name="CODE_BASE64",
                                        value=code_b64,
                                    ),
                                ],
                            )
                        ],
                    ),
                ),
            ),
        )

        self.batch_v1.create_namespaced_job(namespace=self.namespace, body=job)
        logger.info(f"Created sandbox job: {job_name} (execution_id={execution_id})")
        return execution_id

    def wait_for_completion(self, execution_id: str, timeout: int | None = None) -> dict:
        """Poll for job completion. Returns status dict."""
        self._ensure_initialized()

        if timeout is None:
            timeout = settings.sandbox_timeout_seconds

        job_name = f"sandbox-{execution_id[:8]}"
        start_time = time.time()

        while time.time() - start_time < timeout:
            try:
                job = self.batch_v1.read_namespaced_job(
                    name=job_name, namespace=self.namespace
                )
                status = job.status

                if status.succeeded and status.succeeded > 0:
                    logs = self._get_pod_logs(job_name)
                    return {
                        "status": "completed",
                        "execution_id": execution_id,
                        "logs": logs,
                    }
                if status.failed and status.failed > 0:
                    logs = self._get_pod_logs(job_name)
                    return {
                        "status": "failed",
                        "execution_id": execution_id,
                        "logs": logs,
                    }
            except ApiException as e:
                if e.status == 404:
                    return {
                        "status": "not_found",
                        "execution_id": execution_id,
                        "logs": "",
                    }
                raise

            time.sleep(2)

        return {
            "status": "timeout",
            "execution_id": execution_id,
            "logs": "",
        }

    def _get_pod_logs(self, job_name: str) -> str:
        """Get logs from the pod of a job."""
        try:
            pods = self.core_v1.list_namespaced_pod(
                namespace=self.namespace,
                label_selector=f"job-name={job_name}",
            )
            if pods.items:
                pod_name = pods.items[0].metadata.name
                return self.core_v1.read_namespaced_pod_log(
                    name=pod_name, namespace=self.namespace
                )
        except Exception as e:
            logger.warning(f"Failed to get pod logs for {job_name}: {e}")
        return ""


sandbox_service = SandboxService()
