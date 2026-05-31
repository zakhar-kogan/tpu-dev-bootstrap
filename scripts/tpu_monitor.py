#!/usr/bin/env python3
import json
import os
import subprocess
import urllib.request
import urllib.parse
from pathlib import Path

PROJECT = "tpu-research-468103"
CONFIG_DIR = Path.home() / ".config" / "tpu-dev"
CACHE_FILE = CONFIG_DIR / "monitor_cache.json"
SECRETS_FILE = CONFIG_DIR / "secrets.env"

def load_secrets():
    secrets = {}
    if SECRETS_FILE.exists():
        with open(SECRETS_FILE) as f:
            for line in f:
                line = line.strip()
                if line and not line.startswith("#") and "=" in line:
                    k, v = line.split("=", 1)
                    secrets[k.strip()] = v.strip().strip('"').strip("'")
    return secrets

def send_telegram(token, chat_id, text):
    url = f"https://api.telegram.org/bot{token}/sendMessage"
    data = urllib.parse.urlencode({"chat_id": chat_id, "text": text, "parse_mode": "Markdown"}).encode("utf-8")
    try:
        req = urllib.request.Request(url, data=data)
        with urllib.request.urlopen(req) as response:
            return response.read()
    except Exception as e:
        print(f"Failed to send Telegram notification: {e}")

def run_gcloud(cmd):
    try:
        res = subprocess.run(cmd, capture_output=True, text=True, check=True)
        return json.loads(res.stdout)
    except Exception as e:
        print(f"Failed to execute gcloud command {cmd}: {e}")
        return []

def main():
    secrets = load_secrets()
    token = os.environ.get("TELEGRAM_BOT_TOKEN") or secrets.get("TELEGRAM_BOT_TOKEN")
    chat_id = os.environ.get("TELEGRAM_CHAT_ID") or secrets.get("TELEGRAM_CHAT_ID")

    if not token or not chat_id:
        print("Telegram Bot Token or Chat ID not found in environment or secrets.env. Skipping notification.")
        return

    # 1. Fetch current queued resources
    qr_cmd = [
        "gcloud", "compute", "tpus", "queued-resources", "list",
        f"--project={PROJECT}", "--zone=-", "--format=json"
    ]
    qr_data = run_gcloud(qr_cmd)
    
    # 2. Fetch current TPU VMs
    vm_cmd = [
        "gcloud", "compute", "tpus", "tpu-vm", "list",
        f"--project={PROJECT}", "--zone=-", "--format=json"
    ]
    vm_data = run_gcloud(vm_cmd)

    # 3. Process states
    current_states = {}
    
    # Process Queued Resources
    for qr in qr_data:
        # gcloud lists name as e.g. "projects/tpu-research-468103/locations/us-central2-b/queuedResources/cayley-v4-8-spot-qr"
        name_parts = qr.get("name", "").split("/")
        qr_name = name_parts[-1] if name_parts else "unknown"
        zone = name_parts[3] if len(name_parts) > 3 else "unknown"
        
        state_info = qr.get("state", {})
        state = state_info.get("state", "UNKNOWN")
        accel_type = qr.get("tpu", {}).get("nodeSpec", [{}])[0].get("node", {}).get("acceleratorType", "unknown")
        
        # Details about failures if any
        fail_msg = ""
        if "failedData" in state_info:
            fail_msg = f" (Error: {state_info['failedData'].get('error', {}).get('message', 'Unknown Error')})"

        current_states[f"QR:{qr_name}"] = {
            "type": "Queued Resource",
            "name": qr_name,
            "zone": zone,
            "accel": accel_type,
            "state": state + fail_msg
        }

    # Process TPU VMs
    for vm in vm_data:
        name_parts = vm.get("name", "").split("/")
        vm_name = name_parts[-1] if name_parts else "unknown"
        zone = name_parts[3] if len(name_parts) > 3 else "unknown"
        
        state = vm.get("state", "UNKNOWN")
        accel_type = vm.get("acceleratorType", "unknown")
        
        current_states[f"VM:{vm_name}"] = {
            "type": "TPU VM Instance",
            "name": vm_name,
            "zone": zone,
            "accel": accel_type,
            "state": state
        }

    # 4. Load previous states cache
    prev_states = {}
    if CACHE_FILE.exists():
        try:
            with open(CACHE_FILE) as f:
                prev_states = json.load(f)
        except Exception:
            pass

    # 5. Compare states and send notifications
    notifications = []
    
    # Check for state changes or new items
    for key, curr in current_states.items():
        prev = prev_states.get(key)
        if not prev:
            # New item detected
            msg = f"🆕 *New {curr['type']} Detected:*\n• *Name:* `{curr['name']}`\n• *Zone:* `{curr['zone']}`\n• *Type:* `{curr['accel']}`\n• *Initial State:* `{curr['state']}`"
            notifications.append(msg)
        elif prev["state"] != curr["state"]:
            # State changed
            msg = f"🔄 *TPU State Change:*\n• *Resource:* `{curr['name']}` ({curr['type']})\n• *Zone:* `{curr['zone']}`\n• *Type:* `{curr['accel']}`\n• *Old State:* `{prev['state']}`\n• *New State:* `{curr['state']}`"
            notifications.append(msg)

    # Check for removed items
    for key, prev in prev_states.items():
        if key not in current_states:
            msg = f"🗑️ *Resource Removed/Deleted:*\n• *Resource:* `{prev['name']}` ({prev['type']})\n• *Zone:* `{prev['zone']}`\n• *Type:* `{prev['accel']}`"
            notifications.append(msg)

    # 6. Send notifications if any
    if notifications:
        full_text = "\n\n---\n\n".join(notifications)
        send_telegram(token, chat_id, full_text)

    # 7. Save current states as the new cache
    CONFIG_DIR.mkdir(parents=True, exist_ok=True)
    with open(CACHE_FILE, "w") as f:
        json.dump(current_states, f, indent=2)

if __name__ == "__main__":
    main()
