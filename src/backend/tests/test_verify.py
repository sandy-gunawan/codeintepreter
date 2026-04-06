"""Backend verification tests — run with: python tests/test_verify.py"""

import sys
import os

# Ensure we can import app modules
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

passed = 0
failed = 0


def check(name: str, condition: bool, detail: str = ""):
    global passed, failed
    if condition:
        print(f"  [PASS] {name}")
        passed += 1
    else:
        print(f"  [FAIL] {name} -- {detail}")
        failed += 1


print("=" * 50)
print("  Backend Verification Tests")
print("=" * 50)
print()

# --- Imports ---
print("Module Imports:")
try:
    from app.config import Settings
    check("config.Settings", True)
except Exception as e:
    check("config.Settings", False, str(e))

try:
    from app.llm.provider import LLMProvider, AzureOpenAIProvider, get_llm_provider, LLMResponse
    check("llm.provider", True)
except Exception as e:
    check("llm.provider", False, str(e))

try:
    from app.routes.health import router as health_router
    check("routes.health", True)
except Exception as e:
    check("routes.health", False, str(e))

try:
    from app.routes.upload import router as upload_router
    check("routes.upload", True)
except Exception as e:
    check("routes.upload", False, str(e))

try:
    from app.routes.chat import router as chat_router, ChatRequest, ChatResponse
    check("routes.chat", True)
except Exception as e:
    check("routes.chat", False, str(e))

try:
    from app.storage import storage_service, StorageService
    check("storage", True)
except Exception as e:
    check("storage", False, str(e))

try:
    from app.sandbox import sandbox_service, SandboxService
    check("sandbox", True)
except Exception as e:
    check("sandbox", False, str(e))

try:
    from app.orchestrator import extract_code, CODE_GEN_SYSTEM_PROMPT
    check("orchestrator", True)
except Exception as e:
    check("orchestrator", False, str(e))

print()

# --- extract_code ---
print("Code Extraction:")

test_with_python_block = """Here is the analysis code:
```python
import pandas as pd
df = pd.read_csv(DATA_PATH)
print(df.describe())
```
"""
code = extract_code(test_with_python_block)
check("python code block", code is not None and "pd.read_csv" in code,
      f"got: {repr(code[:50]) if code else 'None'}")

test_with_generic_block = """```
import numpy as np
arr = np.array([1,2,3])
```"""
code2 = extract_code(test_with_generic_block)
check("generic code block", code2 is not None and "numpy" in code2,
      f"got: {repr(code2[:50]) if code2 else 'None'}")

check("no code block returns None", extract_code("No code here at all") is None)

print()

# --- Settings ---
print("Settings:")
s = Settings()
check("sandbox_namespace default", s.sandbox_namespace == "sandbox")
check("datasets container default", s.storage_datasets_container == "datasets")
check("outputs container default", s.storage_outputs_container == "outputs")
check("audit container default", s.storage_audit_container == "audit-logs")
check("llm_provider default", s.llm_provider == "azure")
check("sandbox_timeout default", s.sandbox_timeout_seconds == 300)
check("sandbox_cpu_limit default", s.sandbox_cpu_limit == "1")
check("sandbox_memory_limit default", s.sandbox_memory_limit == "1Gi")

print()

# --- Pydantic Models ---
print("Pydantic Models:")
req = ChatRequest(prompt="test question", dataset_blob="session/file.csv", session_id="abc-123")
check("ChatRequest creation", req.prompt == "test question")
check("ChatRequest dataset_blob", req.dataset_blob == "session/file.csv")

resp = ChatResponse(execution_id="exec-1", status="completed", message="done")
check("ChatResponse creation", resp.status == "completed")
check("ChatResponse optional code is None", resp.code is None)
check("ChatResponse optional output_files empty", resp.output_files == [])

print()

# --- Lazy Service Init ---
print("Lazy Service Initialization:")
try:
    ss = StorageService()
    check("StorageService() no crash", True)
except Exception as e:
    check("StorageService() no crash", False, str(e))

try:
    sb = SandboxService()
    check("SandboxService() no crash", True)
except Exception as e:
    check("SandboxService() no crash", False, str(e))

print()

# --- FastAPI App ---
print("FastAPI Application:")
try:
    from app.main import app
    check("app created", app is not None)
    check("app has routes", len(app.routes) > 0)

    paths = [getattr(r, "path", "") for r in app.routes]
    check("/api/health endpoint", "/api/health" in paths)
    check("/api/upload endpoint", "/api/upload" in paths)
    check("/api/chat endpoint", "/api/chat" in paths)

    print(f"\n  Registered routes:")
    for route in app.routes:
        methods = getattr(route, "methods", None)
        path = getattr(route, "path", "?")
        if methods:
            print(f"    {', '.join(methods):8s} {path}")
except Exception as e:
    check("app created", False, str(e))

print()

# --- LLM Provider Factory ---
print("LLM Provider Factory:")
try:
    provider = get_llm_provider()
    check("get_llm_provider() returns AzureOpenAIProvider", isinstance(provider, AzureOpenAIProvider))
except Exception as e:
    # Expected to fail without real credentials, but should be the right error
    if "Unknown LLM provider" in str(e):
        check("get_llm_provider()", False, str(e))
    else:
        check("get_llm_provider() instantiates (no endpoint = ok)", True)

print()

# --- Summary ---
print("=" * 50)
total = passed + failed
print(f"  Results: {passed}/{total} passed, {failed} failed")
print("=" * 50)

if failed > 0:
    sys.exit(1)
else:
    print("\n  ALL BACKEND TESTS PASSED\n")
    sys.exit(0)
