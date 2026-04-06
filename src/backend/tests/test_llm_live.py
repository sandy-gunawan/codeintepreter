"""
End-to-end LLM integration test.
Tests the actual LLM provider with the real Azure OpenAI endpoint.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

# Set env vars for the test — replace with your actual values
os.environ["AZURE_OPENAI_ENDPOINT"] = os.environ.get("AZURE_OPENAI_ENDPOINT", "https://your-openai-endpoint.openai.azure.com")
os.environ["AZURE_OPENAI_KEY"] = os.environ.get("AZURE_OPENAI_KEY", "your-api-key-here")
os.environ["AZURE_OPENAI_DEPLOYMENT"] = os.environ.get("AZURE_OPENAI_DEPLOYMENT", "gpt-4.1")
os.environ["AZURE_OPENAI_API_VERSION"] = "2024-12-01-preview"

passed = 0
failed = 0


def OK(msg):
    global passed
    passed += 1
    print(f"  [PASS] {msg}")


def NG(msg):
    global failed
    failed += 1
    print(f"  [FAIL] {msg}")


print("=" * 60)
print("  LLM Integration Test (Live Azure OpenAI)")
print("=" * 60)
print()

# Test 1: Basic LLM call
print("--- Basic LLM call ---")
try:
    from app.llm.provider import get_llm_provider
    provider = get_llm_provider()
    resp = provider.generate(
        system_prompt="You are a helpful assistant.",
        user_prompt="Say 'hello world' and nothing else.",
    )
    if "hello" in resp.content.lower():
        OK(f"LLM responded: {resp.content.strip()[:50]}")
    else:
        NG(f"Unexpected response: {resp.content[:50]}")
    OK(f"Model: {resp.model}")
    OK(f"Tokens used: {resp.usage['total_tokens']}")
except Exception as e:
    NG(f"LLM call failed: {e}")

print()

# Test 2: Code generation (like the orchestrator does)
print("--- Code generation prompt ---")
try:
    from app.orchestrator import CODE_GEN_SYSTEM_PROMPT, extract_code

    data_preview = """transaction_id,account_id,amount,merchant,channel,date
T001,A123,150000,Tokopedia,Online,2025-01-02
T002,A123,8500000,Unknown,Online,2025-01-03
T003,A123,200000,Indomaret,Offline,2025-01-03"""

    resp = provider.generate(
        system_prompt=CODE_GEN_SYSTEM_PROMPT,
        user_prompt="Identify unusual transactions based on amount",
        context={"data_preview": data_preview},
    )

    code = extract_code(resp.content)
    if code and "pandas" in code.lower():
        OK(f"Generated Python code ({len(code)} chars)")
        # Show first few lines
        for line in code.split("\n")[:5]:
            print(f"    {line}")
        if len(code.split("\n")) > 5:
            print(f"    ... ({len(code.split(chr(10)))} total lines)")
    else:
        NG(f"No valid Python code generated")
        print(f"  Response: {resp.content[:200]}")

    OK(f"Code gen tokens: {resp.usage['total_tokens']}")
except Exception as e:
    NG(f"Code generation failed: {e}")

print()

# Test 3: Explanation generation
print("--- Explanation prompt ---")
try:
    from app.orchestrator import EXPLAIN_SYSTEM_PROMPT

    resp = provider.generate(
        system_prompt=EXPLAIN_SYSTEM_PROMPT,
        user_prompt="""The user asked: "Identify unusual transactions"
Execution output:
```
Mean amount: 1,250,000
Std dev: 2,500,000
Anomalies found:
  T002: 8,500,000 (3.4 std devs above mean)
  T006: 50,000,000 (19.5 std devs above mean)
```
Please explain the results.""",
    )
    if len(resp.content) > 50:
        OK(f"Explanation generated ({len(resp.content)} chars)")
        print(f"    {resp.content[:120]}...")
    else:
        NG(f"Explanation too short: {resp.content}")
except Exception as e:
    NG(f"Explanation generation failed: {e}")

print()

# Summary
print("=" * 60)
total = passed + failed
if failed > 0:
    print(f"  TOTAL: {passed}/{total} PASSED, {failed} FAILED")
else:
    print(f"  TOTAL: {passed}/{total} PASSED")
print("=" * 60)

if failed == 0:
    print("\n  ALL LLM INTEGRATION TESTS PASSED\n")
    sys.exit(0)
else:
    sys.exit(1)
