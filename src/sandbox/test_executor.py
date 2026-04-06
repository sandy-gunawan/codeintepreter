"""Sandbox executor verification test."""

import io
import os
import sys
import shutil
import traceback
from datetime import datetime, timezone
from contextlib import redirect_stdout, redirect_stderr

passed = 0
failed = 0


def check(name, condition, detail=""):
    global passed, failed
    if condition:
        print(f"  [PASS] {name}")
        passed += 1
    else:
        print(f"  [FAIL] {name} -- {detail}")
        failed += 1


def execute_code(code, data_path):
    """Mirror of sandbox executor's execute_code function."""
    stdout_capture = io.StringIO()
    stderr_capture = io.StringIO()
    exec_globals = {
        "__builtins__": __builtins__,
        "DATA_PATH": data_path,
        "OUTPUT_DIR": "test_outputs",
    }
    os.makedirs("test_outputs", exist_ok=True)
    start_time = datetime.now(timezone.utc)
    success = True
    error_message = None
    try:
        with redirect_stdout(stdout_capture), redirect_stderr(stderr_capture):
            exec(code, exec_globals)
    except Exception:
        success = False
        error_message = traceback.format_exc()
    end_time = datetime.now(timezone.utc)
    return {
        "success": success,
        "stdout": stdout_capture.getvalue(),
        "stderr": stderr_capture.getvalue(),
        "error": error_message,
        "duration": (end_time - start_time).total_seconds(),
    }


print("=" * 50)
print("  Sandbox Executor Tests")
print("=" * 50)
print()

# Test 1: basic print
r = execute_code('print("hello from sandbox")', "/tmp/test.csv")
check("basic code execution", r["success"] and "hello from sandbox" in r["stdout"])

# Test 2: pandas import
r2 = execute_code('import pandas as pd\nprint("pandas:", pd.__version__)', "/tmp/test.csv")
check("pandas import", r2["success"] and "pandas:" in r2["stdout"])

# Test 3: numpy
r3 = execute_code('import numpy as np\nprint("sum:", np.sum([1,2,3]))', "/tmp/test.csv")
check("numpy import", r3["success"] and "sum: 6" in r3["stdout"])

# Test 4: matplotlib (save chart)
r4 = execute_code(
    'import matplotlib\nmatplotlib.use("Agg")\nimport matplotlib.pyplot as plt\n'
    'plt.figure()\nplt.plot([1,2,3])\nplt.savefig(f"{OUTPUT_DIR}/test.png")\nplt.close()\n'
    'print("chart saved")',
    "/tmp/test.csv",
)
chart_exists = os.path.exists("test_outputs/test.png")
check("matplotlib chart generation", r4["success"] and chart_exists, f"success={r4['success']}, chart_exists={chart_exists}")

# Test 5: error handling
r5 = execute_code('raise ValueError("intentional test error")', "/tmp/test.csv")
check("error captured", not r5["success"] and "ValueError" in (r5["error"] or ""))

# Test 6: DATA_PATH accessible
r6 = execute_code('print("path:", DATA_PATH)', "/sandbox/input.csv")
check("DATA_PATH variable", r6["success"] and "/sandbox/input.csv" in r6["stdout"])

# Test 7: OUTPUT_DIR accessible
r7 = execute_code('print("outdir:", OUTPUT_DIR)', "/tmp/test.csv")
check("OUTPUT_DIR variable", r7["success"] and "test_outputs" in r7["stdout"])

# Test 8: seaborn
r8 = execute_code('import seaborn as sns\nprint("seaborn:", sns.__version__)', "/tmp/test.csv")
check("seaborn import", r8["success"] and "seaborn:" in r8["stdout"])

# Test 9: CSV write to output
r9 = execute_code(
    'import pandas as pd\n'
    'df = pd.DataFrame({"a": [1,2], "b": [3,4]})\n'
    'df.to_csv(f"{OUTPUT_DIR}/result.csv", index=False)\n'
    'print("csv written")',
    "/tmp/test.csv",
)
csv_exists = os.path.exists("test_outputs/result.csv")
check("CSV output generation", r9["success"] and csv_exists)

# Cleanup
shutil.rmtree("test_outputs", ignore_errors=True)

print()
print("=" * 50)
total = passed + failed
print(f"  Results: {passed}/{total} passed, {failed} failed")
print("=" * 50)

if failed > 0:
    sys.exit(1)
else:
    print("\n  ALL SANDBOX EXECUTOR TESTS PASSED\n")
    sys.exit(0)
