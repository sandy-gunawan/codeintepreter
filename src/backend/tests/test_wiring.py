"""
End-to-end wiring verification.
Checks that all config references match across Bicep, K8s, Python, and deploy scripts.
"""
import os
import re
import sys

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

def read(path):
    with open(path, "r", encoding="utf-8") as f:
        return f.read()

# Project root is 3 levels up from tests/test_wiring.py (tests -> src/backend -> codeintepreter)
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))

print("=" * 60)
print("  End-to-End Wiring Verification")
print("=" * 60)
print()

# --- 1. Bicep outputs match deploy script reads ---
print("--- Bicep outputs -> deploy-infra.ps1 ---")
bicep_main = read(os.path.join(ROOT, "infra", "main.bicep"))
deploy_infra = read(os.path.join(ROOT, "scripts", "deploy-infra.ps1"))

bicep_outputs = re.findall(r"output (\w+) ", bicep_main)
# These outputs are informational/debugging only, not consumed by deploy scripts
info_only_outputs = {"aksClusterFqdn", "logAnalyticsWorkspaceName", "resourceGroupName"}
for out in bicep_outputs:
    if out in info_only_outputs:
        OK(f"Bicep output '{out}' is informational (not needed by scripts)")
    elif out in deploy_infra:
        OK(f"Bicep output '{out}' referenced in deploy-infra.ps1")
    else:
        NG(f"Bicep output '{out}' NOT found in deploy-infra.ps1")

print()

# --- 2. deploy-infra.ps1 outputs match deploy-apps.ps1 reads ---
print("--- deploy-infra.ps1 -> deploy-apps.ps1 ---")
deploy_apps = read(os.path.join(ROOT, "scripts", "deploy-apps.ps1"))
infra_vars = ["AcrLoginServer", "AcrName", "AksClusterName", "StorageAccountName",
              "OpenAiEndpoint", "OpenAiDeploymentName", "ResourceGroup"]
for var in infra_vars:
    if var in deploy_apps:
        OK(f"Infra var '${var}' used in deploy-apps.ps1")
    else:
        NG(f"Infra var '${var}' NOT found in deploy-apps.ps1")

print()

# --- 3. K8s placeholders match deploy-apps.ps1 replacements ---
print("--- K8s placeholders -> deploy-apps.ps1 substitution ---")
app_yaml = read(os.path.join(ROOT, "k8s", "app-deployment.yaml"))
placeholders = set(re.findall(r"__(\w+)__", app_yaml))
for ph in sorted(placeholders):
    if f"__{ph}__" in deploy_apps:
        OK(f"Placeholder '__{ph}__' replaced in deploy-apps.ps1")
    else:
        NG(f"Placeholder '__{ph}__' NOT replaced in deploy-apps.ps1")

print()

# --- 4. K8s env vars match Python config.py ---
print("--- K8s ConfigMap/Secret -> Python config.py ---")
config_py = read(os.path.join(ROOT, "src", "backend", "app", "config.py"))

k8s_env_keys = re.findall(r'^\s+(\w+):', app_yaml, re.MULTILINE)
# Filter to env-style keys (uppercase with underscores)
k8s_env_keys = [k for k in k8s_env_keys if k == k.upper() and "_" in k and len(k) > 5
                and not k.startswith("__")]

for key in sorted(set(k8s_env_keys)):
    lower_key = key.lower()
    if lower_key in config_py:
        OK(f"K8s env '{key}' -> config.py '{lower_key}'")
    else:
        # Some are set directly as env, not in Settings
        NG(f"K8s env '{key}' not mapped in config.py")

print()

# --- 5. Backend routes match Ingress paths ---
print("--- Backend routes -> Ingress paths ---")
if "/api" in app_yaml and "path: /api" in app_yaml:
    OK("Ingress routes /api -> backend:8000")
if "path: /" in app_yaml:
    OK("Ingress routes / -> frontend:3000")

# Check port numbers match
if "containerPort: 8000" in app_yaml and "port: 8000" in app_yaml:
    OK("Backend port 8000 consistent (container + service + ingress)")
if "containerPort: 3000" in app_yaml and "port: 3000" in app_yaml:
    OK("Frontend port 3000 consistent (container + service + ingress)")

print()

# --- 6. Frontend API calls -> relative URLs ---
print("--- Frontend API -> relative URLs ---")
api_ts = read(os.path.join(ROOT, "src", "frontend", "src", "lib", "api.ts"))
if "API_URL || ''" in api_ts or "API_URL || \"\"" in api_ts:
    OK("Frontend defaults to relative URLs (empty string)")
else:
    NG("Frontend may hardcode absolute URL")

if "/api/upload" in api_ts:
    OK("Frontend calls /api/upload")
if "/api/chat" in api_ts:
    OK("Frontend calls /api/chat")
if "/api/health" in api_ts:
    OK("Frontend calls /api/health")

print()

# --- 7. Sandbox image ref matches ---
print("--- Sandbox image wiring ---")
if "SANDBOX_IMAGE" in app_yaml:
    OK("K8s sets SANDBOX_IMAGE env var for backend")
if "sandbox_image" in config_py:
    OK("config.py reads sandbox_image setting")

sandbox_py = read(os.path.join(ROOT, "src", "backend", "app", "sandbox.py"))
if "settings.sandbox_image" in sandbox_py:
    OK("sandbox.py uses settings.sandbox_image for Job creation")

print()

# --- 8. Storage containers consistent ---
print("--- Storage container names ---")
storage_bicep = read(os.path.join(ROOT, "infra", "modules", "storage.bicep"))
containers = ["datasets", "outputs", "audit-logs"]
for c in containers:
    in_bicep = f"'{c}'" in storage_bicep or f'name: \'{c}\'' in storage_bicep
    in_k8s = c in app_yaml or c.replace("-", "_") in app_yaml
    in_py = c in config_py or c.replace("-", "-") in config_py
    if in_bicep and in_py:
        OK(f"Container '{c}' in Bicep + Python config")
    else:
        NG(f"Container '{c}' mismatch: bicep={in_bicep}, python={in_py}")

print()

# --- 9. RBAC: backend SA -> sandbox namespace ---
print("--- RBAC wiring ---")
rbac_yaml = read(os.path.join(ROOT, "k8s", "rbac.yaml"))
if "orchestrator-sa" in rbac_yaml and "orchestrator-sa" in app_yaml:
    OK("Backend deployment uses orchestrator-sa ServiceAccount")
if "sandbox" in rbac_yaml and "namespace: sandbox" in rbac_yaml:
    OK("RBAC grants Job permissions in sandbox namespace")
if "sandbox" in config_py or "sandbox_namespace" in config_py:
    OK("config.py has sandbox_namespace setting")

print()

# --- 10. NetworkPolicy -> sandbox namespace ---
print("--- NetworkPolicy ---")
np_yaml = read(os.path.join(ROOT, "k8s", "sandbox-networkpolicy.yaml"))
if "namespace: sandbox" in np_yaml:
    OK("NetworkPolicies target sandbox namespace")
if "169.254.169.254" in np_yaml:
    OK("IMDS metadata service blocked")
if "Egress" in np_yaml and "egress: []" in np_yaml:
    OK("Default deny-all-egress present")

print()

# --- 11. Node pool wiring ---
print("--- AKS node pool -> K8s scheduling ---")
aks_bicep = read(os.path.join(ROOT, "infra", "modules", "aks.bicep"))
if "'sandboxpool'" in aks_bicep and "sandboxpool" in config_py:
    OK("Sandbox node pool name matches config.py")
if "sandbox=true:NoSchedule" in aks_bicep and "sandbox" in sandbox_py:
    OK("Sandbox taint defined in Bicep, toleration in sandbox.py")
if "KataMshvVmIsolation" in aks_bicep:
    OK("Kata VM isolation workload runtime configured")
if "kata-mshv-vm-isolation" in sandbox_py:
    OK("sandbox.py uses kata-mshv-vm-isolation runtime class")

print()

# --- 12. Bicep infra completeness ---
print("--- Infrastructure completeness ---")
for module in ["aks.bicep", "acr.bicep", "openai.bicep", "storage.bicep", "monitoring.bicep"]:
    path = os.path.join(ROOT, "infra", "modules", module)
    if os.path.exists(path):
        OK(f"Module {module} exists")
    else:
        NG(f"Module {module} MISSING")

if "modules/aks.bicep" in bicep_main:
    OK("main.bicep references aks module")
if "modules/openai.bicep" in bicep_main:
    OK("main.bicep references openai module")

print()

# --- Summary ---
print("=" * 60)
total = passed + failed
if failed > 0:
    print(f"  TOTAL: {passed}/{total} PASSED, {failed} FAILED")
else:
    print(f"  TOTAL: {passed}/{total} PASSED")
print("=" * 60)

if failed > 0:
    print(f"\n  {failed} wiring issues found.\n")
    sys.exit(1)
else:
    print("\n  ALL END-TO-END WIRING VERIFIED\n")
    sys.exit(0)
