#!/usr/bin/env python3
"""
Parallel kustomize validation script
Validates all kustomizations quickly and quietly (unless errors occur)
"""

import asyncio
import sys
import json
from pathlib import Path
import argparse


async def validate_kustomization(kustomization_path: Path) -> tuple[Path, bool, str]:
    """Validate a single kustomization directory"""
    try:
        proc = await asyncio.create_subprocess_exec(
            "kustomize",
            "build",
            str(kustomization_path.parent),
            stdout=asyncio.subprocess.DEVNULL,
            stderr=asyncio.subprocess.PIPE,
        )
        _, stderr = await proc.communicate()

        if proc.returncode == 0:
            return kustomization_path, True, ""
        else:
            return kustomization_path, False, stderr.decode()
    except Exception as e:
        return kustomization_path, False, str(e)


async def main():
    parser = argparse.ArgumentParser(description="Validate kustomizations in parallel")
    parser.add_argument(
        "--verbose", "-v", action="store_true", help="Show successful validations"
    )
    parser.add_argument(
        "--root", default="k8s/", help="Root directory to search for kustomizations"
    )
    parser.add_argument(
        "--format",
        choices=["human", "json"],
        default="human",
        help="Output format (human or json for Terraform)",
    )
    args = parser.parse_args()

    # Find all kustomization.yaml files (excluding flux-system)
    root = Path(args.root)
    kustomizations = []

    for kustomization_file in root.rglob("kustomization.yaml"):
        if "flux-system" not in kustomization_file.parts:
            kustomizations.append(kustomization_file)

    if not kustomizations:
        print(f"No kustomizations found in {root}")
        return 0

    # Validate all kustomizations in parallel
    tasks = [validate_kustomization(k) for k in kustomizations]
    results = await asyncio.gather(*tasks)

    # Process results
    successful = []
    failed = []

    for kustomization, success, error in results:
        if success:
            successful.append(kustomization)
        else:
            failed.append((kustomization, error))

    # Output results
    if args.format == "json":
        # JSON output for Terraform data source
        if failed:
            error_details = [
                {"path": str(k.parent), "error": error.strip()} for k, error in failed
            ]
            result = {
                "error": f"Failed to validate {len(failed)} kustomizations",
                "details": error_details,
            }
            print(json.dumps(result), file=sys.stderr)
            return 1
        else:
            result = {"status": "passed", "validated_count": len(successful)}
            print(json.dumps(result))
            return 0
    else:
        # Human-readable output
        if args.verbose and successful:
            print(f"✅ Successfully validated {len(successful)} kustomizations:")
            for k in successful:
                print(f"  {k.parent}")

        if failed:
            print(f"❌ Failed to validate {len(failed)} kustomizations:")
            for kustomization, error in failed:
                print(f"  {kustomization.parent}:")
                print(f"    {error.strip()}")
            return 1

        if not args.verbose:
            print(f"✅ All {len(successful)} kustomizations valid")

        return 0


if __name__ == "__main__":
    sys.exit(asyncio.run(main()))
