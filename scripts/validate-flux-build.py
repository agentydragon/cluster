#!/usr/bin/env python3
"""
Flux Build Validation Script
Validates that Flux can build all kustomizations and analyzes the results.
Requires flux CLI to be available - does not fall back to alternatives.
"""

import subprocess
import sys
import yaml
from collections import defaultdict
from typing import List, Tuple


def run_flux_build() -> Tuple[bool, str, str]:
    """Run flux build and capture output - fail if flux is not available"""
    try:
        # Try flux build with dry-run (requires kustomization file)
        kustomization_file = "./k8s/flux-system/gotk-sync.yaml"
        result = subprocess.run(
            [
                "flux",
                "build",
                "kustomization",
                "flux-system",
                "--path",
                "./k8s",
                "--kustomization-file",
                kustomization_file,
                "--dry-run",
            ],
            capture_output=True,
            text=True,
            timeout=60,
        )

        return result.returncode == 0, result.stdout, result.stderr

    except FileNotFoundError:
        return False, "", "flux CLI not found - ensure flux is installed and available"
    except subprocess.TimeoutExpired:
        return False, "", "flux build timed out after 60 seconds"
    except Exception as e:
        return False, "", f"flux build failed: {str(e)}"


def analyze_flux_output(output: str) -> List[str]:
    """Analyze the flux build output for potential issues"""
    warnings = []

    try:
        # Parse YAML documents from flux build output
        documents = list(yaml.safe_load_all(output))

        # Count resources by type
        resource_counts = defaultdict(int)
        namespaces = set()

        for doc in documents:
            if not doc:
                continue

            kind = doc.get("kind")
            if kind:
                resource_counts[kind] += 1

            namespace = doc.get("metadata", {}).get("namespace")
            if namespace:
                namespaces.add(namespace)

        # Check for suspicious patterns
        if resource_counts.get("HelmRelease", 0) == 0:
            warnings.append(
                "⚠️  No HelmRelease resources found - expected for GitOps deployment"
            )

        if resource_counts.get("Kustomization", 0) == 0:
            warnings.append("⚠️  No Flux Kustomization resources found")

        # Check for duplicate external-secrets (redundant with other script but good double-check)
        external_secrets_count = 0
        for doc in documents:
            if (
                doc
                and doc.get("kind") == "HelmRelease"
                and doc.get("metadata", {}).get("name") == "external-secrets"
            ):
                external_secrets_count += 1

        if external_secrets_count > 1:
            warnings.append(
                f"❌ Found {external_secrets_count} external-secrets HelmReleases (should be exactly 1)"
            )
        elif external_secrets_count == 0:
            warnings.append("⚠️  No external-secrets HelmRelease found")

        # Summary
        total_resources = sum(resource_counts.values())
        if total_resources > 0:
            print(
                f"📊 Flux build generated {total_resources} resources across {len(namespaces)} namespaces"
            )

            # Show top resource types
            top_resources = sorted(
                resource_counts.items(), key=lambda x: x[1], reverse=True
            )[:5]
            for resource_type, count in top_resources:
                print(f"   {resource_type}: {count}")

    except yaml.YAMLError as e:
        warnings.append(f"⚠️  Failed to parse flux build output as YAML: {e}")
    except Exception as e:
        warnings.append(f"⚠️  Error analyzing flux build output: {e}")

    return warnings


def main():
    """Main validation function"""
    print("🔧 Running flux build validation...")

    # Run flux build
    success, stdout, stderr = run_flux_build()

    if not success:
        print("❌ flux build failed:")
        if stderr:
            print(stderr)
        return 1

    # Analyze the output
    warnings = analyze_flux_output(stdout)

    # Report results
    if warnings:
        print("\nValidation warnings:")
        for warning in warnings:
            print(warning)

        # Only fail on errors (❌), not warnings (⚠️)
        error_count = sum(1 for w in warnings if w.startswith("❌"))
        if error_count > 0:
            return 1

    print("✅ Flux build validation passed!")
    return 0


if __name__ == "__main__":
    sys.exit(main())
