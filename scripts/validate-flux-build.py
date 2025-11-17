#!/usr/bin/env python3
"""
Flux Build Validation Script
Validates that Flux can build all kustomizations and analyzes the results
"""

import subprocess
import sys
import yaml
from collections import defaultdict
from typing import List, Tuple


def run_kustomize_build() -> Tuple[bool, str, str]:
    """Run kustomize build as fallback when flux build requires cluster access"""
    try:
        result = subprocess.run(
            ["kustomize", "build", "./k8s"], capture_output=True, text=True, timeout=60
        )
        return result.returncode == 0, result.stdout, result.stderr

    except subprocess.TimeoutExpired:
        return False, "", "kustomize build timed out after 60 seconds"
    except FileNotFoundError:
        return False, "", "kustomize command not found - ensure kustomize is installed"
    except Exception as e:
        return False, "", f"kustomize build failed: {str(e)}"


def run_flux_build() -> Tuple[bool, str, str]:
    """Run flux build and capture output, with kustomize fallback"""
    try:
        # First try flux build with dry-run (requires kustomization file)
        kustomization_file = "./k8s/flux-system/flux-kustomization.yaml"
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

        if result.returncode == 0:
            return True, result.stdout, result.stderr

        # If flux build fails (no cluster access, etc.), fall back to kustomize
        print("⚠️  Flux build not available, falling back to kustomize build...")
        return run_kustomize_build()

    except FileNotFoundError:
        print("⚠️  Flux CLI not found, falling back to kustomize build...")
        return run_kustomize_build()
    except Exception as e:
        print(f"⚠️  Flux build failed ({e}), falling back to kustomize build...")
        return run_kustomize_build()


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
