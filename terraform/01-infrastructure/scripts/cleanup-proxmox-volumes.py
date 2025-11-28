#!/usr/bin/env python3
"""
Cleanup Proxmox volumes for retained PVs during terraform destroy.

Strategy:
1. Query Kubernetes for Proxmox CSI PV volume handles
2. Extract Proxmox volume IDs from handles
3. Delete volumes via SSH to Proxmox host
4. Fallback to querying Proxmox directly if cluster is down
"""

import sys
import subprocess
import json
from typing import List


def get_volumes_from_kubernetes(kubeconfig_path: str) -> List[str]:
    """Get Proxmox volume IDs from Kubernetes PVs."""
    try:
        result = subprocess.run(
            ["kubectl", f"--kubeconfig={kubeconfig_path}", "get", "pv", "-o", "json"],
            capture_output=True,
            text=True,
            timeout=10,
        )
        if result.returncode != 0:
            return []

        pvs = json.loads(result.stdout)
        volumes = []

        for item in pvs.get("items", []):
            spec = item.get("spec", {})

            # Filter for Proxmox CSI with retain policy
            if (
                spec.get("storageClassName") == "proxmox-csi-retain"
                and spec.get("csi", {}).get("driver") == "csi.proxmox.sinextra.dev"
            ):
                # Extract volume handle: cluster/atlas/local/9999/vm-9999-pvc-XXX.raw
                # Convert to: local:9999/vm-9999-pvc-XXX.raw
                volume_handle = spec.get("csi", {}).get("volumeHandle", "")
                if volume_handle:
                    # Remove "cluster/<node>/" prefix
                    parts = volume_handle.split("/")
                    if len(parts) >= 3:
                        # Rejoin storage/vmid/volume with : separator after storage
                        volume_id = f"{parts[2]}:{'/'.join(parts[3:])}"
                        volumes.append(volume_id)

        return volumes

    except (subprocess.TimeoutExpired, json.JSONDecodeError, Exception):
        return []


def get_volumes_from_proxmox(proxmox_host: str) -> List[str]:
    """Fallback: Query Proxmox directly for all pvc-* volumes."""
    try:
        result = subprocess.run(
            ["ssh", proxmox_host, "pvesm list local"],
            capture_output=True,
            text=True,
            timeout=10,
        )
        if result.returncode != 0:
            return []

        volumes = []
        for line in result.stdout.splitlines():
            # Look for lines with "local:" and "pvc-"
            if "local:" in line and "pvc-" in line:
                # First column is volume ID: "local:9999/vm-9999-pvc-XXX.raw"
                volume_id = line.split()[0]
                volumes.append(volume_id)

        return volumes

    except (subprocess.TimeoutExpired, Exception):
        return []


def delete_volume(proxmox_host: str, volume_id: str) -> bool:
    """Delete a volume from Proxmox storage."""
    try:
        result = subprocess.run(
            ["ssh", proxmox_host, f"pvesm free {volume_id}"],
            capture_output=True,
            timeout=30,
        )
        return result.returncode == 0
    except (subprocess.TimeoutExpired, Exception):
        return False


def main():
    kubeconfig_path = sys.argv[1] if len(sys.argv) > 1 else "./kubeconfig"
    proxmox_host = sys.argv[2] if len(sys.argv) > 2 else "root@atlas"

    print("🧹 Cleaning up Proxmox volumes from retained PVs...")

    # Try Kubernetes first
    volumes = get_volumes_from_kubernetes(kubeconfig_path)

    if volumes:
        print(f"📋 Querying Kubernetes found {len(volumes)} volumes")
    else:
        # Fallback to Proxmox direct query
        print("⚠️  Cluster API unavailable, querying Proxmox directly...")
        volumes = get_volumes_from_proxmox(proxmox_host)
        if volumes:
            print(f"📋 Proxmox query found {len(volumes)} pvc-* volumes")

    if not volumes:
        print("ℹ️  No volumes found to clean up")
        return 0

    print("📋 Found volumes to delete:")
    for vol in volumes:
        print(f"  - {vol}")

    # Delete each volume
    cleaned = 0
    failed = 0

    for vol in volumes:
        print(f"🗑️  Deleting: {vol}")
        if delete_volume(proxmox_host, vol):
            cleaned += 1
        else:
            print(f"⚠️  Failed to delete {vol} (may not exist)")
            failed += 1

    print(f"✅ Cleanup complete: {cleaned} deleted, {failed} failed/not found")
    return 0


if __name__ == "__main__":
    sys.exit(main())
