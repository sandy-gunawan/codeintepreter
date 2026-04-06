"""Orchestrator — coordinates LLM reasoning, sandbox execution, and result explanation."""

import logging
import re
import uuid
from datetime import datetime, timezone

from app.llm.provider import get_llm_provider
from app.storage import storage_service
from app.sandbox import sandbox_service

logger = logging.getLogger(__name__)

CODE_GEN_SYSTEM_PROMPT = """You are a data analysis assistant for a banking application.
You write Python code to analyze datasets. The user will provide a question about their data.

RULES:
1. Write executable Python code that analyzes the data.
2. The input data file path is available as the variable DATA_PATH.
3. Use pandas to load and process data: `import pandas as pd; df = pd.read_csv(DATA_PATH)`
4. Save any charts as PNG to the OUTPUT_DIR directory: e.g., `plt.savefig(f"{OUTPUT_DIR}/chart.png")`
5. Save any result tables as CSV to OUTPUT_DIR: e.g., `result.to_csv(f"{OUTPUT_DIR}/results.csv", index=False)`
6. Print key findings to stdout using print() statements.
7. Do NOT use plt.show() — use plt.savefig() instead.
8. Always close figures after saving: plt.close()
9. Available libraries: pandas, numpy, matplotlib, seaborn, scipy, openpyxl
10. Wrap your code in a ```python code block.

The data preview will be provided so you can understand the schema."""

EXPLAIN_SYSTEM_PROMPT = """You are a data analysis assistant for a banking application.
Given the execution results of a Python analysis, provide a clear, concise explanation
of the findings. Format your response in markdown with:
- A brief summary of what was analyzed
- Key findings (use bullet points)
- Any recommendations or insights
- Reference any generated charts or tables

Keep the language professional and suitable for bank analysts."""


def extract_code(llm_response: str) -> str | None:
    """Extract Python code from LLM response."""
    pattern = r"```python\s*\n(.*?)```"
    matches = re.findall(pattern, llm_response, re.DOTALL)
    if matches:
        return matches[0].strip()

    pattern = r"```\s*\n(.*?)```"
    matches = re.findall(pattern, llm_response, re.DOTALL)
    if matches:
        return matches[0].strip()

    return None


async def process_chat(user_prompt: str, dataset_blob: str, session_id: str) -> dict:
    """
    Full orchestration flow:
    1. Get data preview
    2. Ask LLM to generate code
    3. Execute code in sandbox
    4. Get results
    5. Ask LLM to explain results
    6. Return combined response
    """
    execution_id = str(uuid.uuid4())
    llm = get_llm_provider()

    # Step 1: Get data preview
    try:
        data_preview = storage_service.get_data_preview(dataset_blob)
    except Exception as e:
        logger.error(f"Failed to get data preview: {e}")
        return {
            "execution_id": execution_id,
            "status": "error",
            "message": f"Failed to read dataset: {e}",
            "code": None,
            "explanation": None,
            "output_files": [],
        }

    # Step 2: Ask LLM to generate code
    logger.info(f"[{execution_id}] Generating code for prompt: {user_prompt[:100]}...")
    code_response = llm.generate(
        system_prompt=CODE_GEN_SYSTEM_PROMPT,
        user_prompt=user_prompt,
        context={"data_preview": data_preview},
    )

    code = extract_code(code_response.content)
    if not code:
        return {
            "execution_id": execution_id,
            "status": "error",
            "message": "LLM did not generate executable code.",
            "llm_response": code_response.content,
            "code": None,
            "explanation": code_response.content,
            "output_files": [],
        }

    logger.info(f"[{execution_id}] Code extracted, creating sandbox job...")

    # Step 3: Execute in sandbox
    sas_tokens = storage_service.get_sandbox_sas_tokens()
    account_url = f"https://{storage_service.client.account_name}.blob.core.windows.net"
    sandbox_service.create_execution(
        code=code,
        input_blob=dataset_blob,
        storage_account_url=account_url,
        sas_tokens=sas_tokens,
        execution_id=execution_id,
    )

    # Step 4: Wait for results
    result = sandbox_service.wait_for_completion(execution_id)
    logger.info(f"[{execution_id}] Sandbox result: {result['status']}")

    # Step 5: Get manifest from storage
    manifest = storage_service.get_execution_manifest(execution_id)

    output_files = []
    stdout = ""
    stderr = ""

    if manifest:
        stdout = manifest.get("stdout", "")
        stderr = manifest.get("stderr", "")
        for output_path in manifest.get("output_files", []):
            try:
                url = storage_service.get_output_file_url(output_path)
                output_files.append({
                    "path": output_path,
                    "url": url,
                    "type": "image" if output_path.endswith(".png") else "data",
                })
            except Exception as e:
                logger.warning(f"Failed to get URL for {output_path}: {e}")

    # Step 6: Ask LLM to explain results
    explanation = ""
    if result["status"] == "completed" and stdout:
        explain_prompt = f"""The user asked: "{user_prompt}"

The following Python code was executed:
```python
{code}
```

Execution output (stdout):
```
{stdout}
```

{"Errors (stderr): " + stderr if stderr else ""}

{"Generated files: " + ", ".join(f["path"] for f in output_files) if output_files else "No output files generated."}

Please explain the results to the user."""

        explain_response = llm.generate(
            system_prompt=EXPLAIN_SYSTEM_PROMPT,
            user_prompt=explain_prompt,
        )
        explanation = explain_response.content
    elif result["status"] == "failed":
        explanation = f"Code execution failed.\n\n**Error:**\n```\n{stderr or result.get('logs', 'Unknown error')}\n```"
    elif result["status"] == "timeout":
        explanation = "Code execution timed out. The analysis may be too complex or the dataset too large."

    # Step 7: Write audit log
    audit_entry = {
        "execution_id": execution_id,
        "session_id": session_id,
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "user_prompt": user_prompt,
        "dataset_blob": dataset_blob,
        "code": code,
        "status": result["status"],
        "stdout": stdout[:2000],
        "stderr": stderr[:2000],
        "output_files": [f["path"] for f in output_files],
    }
    try:
        storage_service.write_audit_log(audit_entry)
    except Exception as e:
        logger.warning(f"Failed to write audit log: {e}")

    return {
        "execution_id": execution_id,
        "status": result["status"],
        "message": "Analysis complete" if result["status"] == "completed" else result["status"],
        "code": code,
        "explanation": explanation,
        "output_files": output_files,
    }
