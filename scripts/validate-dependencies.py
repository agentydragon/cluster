#!/usr/bin/env python3
"""
GitOps Dependency Validation Script
Validates Flux kustomization dependencies are correctly ordered and logical
"""

import sys
import yaml
from pathlib import Path
from typing import Dict, List, Set, Optional
from collections import defaultdict
from dataclasses import dataclass


@dataclass
class DependsOn:
    name: str
    namespace: Optional[str] = None


@dataclass
class KustomizationSpec:
    path: str
    depends_on: List[DependsOn]

    @classmethod
    def from_dict(cls, spec_dict: Dict) -> "KustomizationSpec":
        depends_on = []
        for dep in spec_dict.get("dependsOn", []):
            if isinstance(dep, dict) and dep.get("name"):
                depends_on.append(
                    DependsOn(name=dep["name"], namespace=dep.get("namespace"))
                )

        return cls(path=spec_dict.get("path", ""), depends_on=depends_on)


def load_kustomizations(root: Path = Path("k8s")) -> Dict[str, KustomizationSpec]:
    """Load all Flux kustomizations from the repository"""
    kustomizations = {}

    for flux_kustomization_file in root.rglob("flux-kustomization.yaml"):
        try:
            with open(flux_kustomization_file, "r") as f:
                docs = list(yaml.safe_load_all(f))
                for doc in docs:
                    if (
                        doc
                        and doc.get("kind") == "Kustomization"
                        and doc.get("apiVersion", "").startswith(
                            "kustomize.toolkit.fluxcd.io"
                        )
                    ):
                        name = doc.get("metadata", {}).get("name")
                        if name:
                            kustomizations[name] = KustomizationSpec.from_dict(
                                doc.get("spec", {})
                            )
        except Exception as e:
            print(
                f"Warning: Failed to parse {flux_kustomization_file}: {e}",
                file=sys.stderr,
            )

    return kustomizations


def build_dependency_graph(
    kustomizations: Dict[str, KustomizationSpec],
) -> Dict[str, List[str]]:
    """Build dependency graph from kustomizations"""
    graph = defaultdict(list)

    for name, spec in kustomizations.items():
        depends_on = spec.depends_on
        for dep in depends_on:
            graph[dep.name].append(name)

    return dict(graph)


def find_cycles(graph: Dict[str, List[str]], all_nodes: Set[str]) -> List[List[str]]:
    """Find cycles in dependency graph using DFS"""
    WHITE, GRAY, BLACK = 0, 1, 2
    color = {node: WHITE for node in all_nodes}
    cycles = []

    def dfs(node: str, path: List[str]):
        if color[node] == GRAY:
            # Found cycle
            cycle_start = path.index(node)
            cycles.append(path[cycle_start:] + [node])
            return

        if color[node] == BLACK:
            return

        color[node] = GRAY
        path.append(node)

        for neighbor in graph.get(node, []):
            dfs(neighbor, path)

        path.pop()
        color[node] = BLACK

    for node in all_nodes:
        if color[node] == WHITE:
            dfs(node, [])

    return cycles


def check_required_dependencies() -> List[str]:
    """Check that critical dependencies are correctly set up"""
    errors = []

    # Define critical dependency rules
    dependency_rules = {
        "external-secrets-config": {
            "must_come_before": ["authentik", "gitea", "harbor", "powerdns", "matrix"],
            "reason": "Applications need external-secrets ClusterSecretStore to sync secrets from Vault",
        },
        "cert-manager": {
            "must_come_before": ["ingress-nginx", "authentik", "gitea", "harbor"],
            "reason": "TLS certificates required for ingress and applications",
        },
        "ingress-nginx": {
            "must_come_before": ["authentik", "gitea", "harbor", "matrix"],
            "reason": "Applications need ingress controller for external access",
        },
        "vault": {
            "must_come_before": [
                "external-secrets-operator",
                "external-secrets-config",
            ],
            "reason": "Vault must be ready before external-secrets can connect",
        },
        "metallb-config": {
            "must_come_before": ["ingress-nginx"],
            "reason": "Load balancer needed for ingress controller",
        },
    }

    kustomizations = load_kustomizations()

    # Build reverse dependency lookup
    depends_on_map = {}
    for name, spec in kustomizations.items():
        depends_on_map[name] = [dep.name for dep in spec.depends_on]

    def has_dependency_path(
        from_kust: str, to_kust: str, visited: Set[str] = None
    ) -> bool:
        """Check if there's a dependency path from from_kust to to_kust"""
        if visited is None:
            visited = set()

        if from_kust in visited:
            return False

        if from_kust == to_kust:
            return True

        visited.add(from_kust)

        for dep in depends_on_map.get(to_kust, []):
            if has_dependency_path(from_kust, dep, visited):
                return True

        return False

    # Check each dependency rule
    for prereq, rule in dependency_rules.items():
        if prereq not in kustomizations:
            continue

        for dependent in rule["must_come_before"]:
            if dependent not in kustomizations:
                continue

            # Check if dependent has prereq in its dependency chain
            if prereq not in depends_on_map.get(dependent, []):
                # Also check for transitive dependencies
                has_transitive_dep = False
                for dep in depends_on_map.get(dependent, []):
                    if has_dependency_path(prereq, dep):
                        has_transitive_dep = True
                        break

                if not has_transitive_dep:
                    errors.append(
                        f"❌ {dependent} should depend on {prereq} ({rule['reason']})"
                    )

    return errors


def validate_external_secrets_dependencies() -> List[str]:
    """Validate external-secrets specific dependency patterns"""
    errors = []
    kustomizations = load_kustomizations()

    # Check that services using ExternalSecret resources depend on external-secrets
    services_with_external_secrets = []

    for kust_file in Path("k8s").rglob("*.yaml"):
        if "flux-kustomization" in kust_file.name:
            continue

        try:
            with open(kust_file, "r") as f:
                docs = list(yaml.safe_load_all(f))
                for doc in docs:
                    if (
                        doc
                        and doc.get("kind") == "ExternalSecret"
                        and doc.get("apiVersion", "").startswith("external-secrets.io")
                    ):
                        # Find which kustomization this belongs to
                        relative_path = kust_file.relative_to(Path("k8s"))
                        service_name = (
                            relative_path.parts[0] if relative_path.parts else None
                        )
                        if (
                            service_name
                            and service_name not in services_with_external_secrets
                        ):
                            services_with_external_secrets.append(service_name)
        except Exception:
            continue

    # Check dependencies
    for service in services_with_external_secrets:
        if service in kustomizations:
            deps = [dep.name for dep in kustomizations[service].depends_on]
            if "external-secrets-config" not in deps:
                errors.append(
                    f"❌ {service} uses ExternalSecret resources but doesn't depend on external-secrets-config kustomization"
                )

    return errors


def main():
    """Main validation function"""
    print("🔍 Validating GitOps dependencies...")

    errors = []

    try:
        # Load all kustomizations
        kustomizations = load_kustomizations()

        if not kustomizations:
            print("❌ No Flux kustomizations found!")
            return 1

        print(f"📋 Found {len(kustomizations)} kustomizations")

        # Build dependency graph
        graph = build_dependency_graph(kustomizations)
        all_nodes = set(kustomizations.keys()) | set().union(*graph.values())

        # Check for circular dependencies
        cycles = find_cycles(graph, all_nodes)
        if cycles:
            errors.append("❌ Circular dependencies detected:")
            for cycle in cycles:
                errors.append(f"   {' → '.join(cycle)}")

        # Check required dependencies
        required_errors = check_required_dependencies()
        errors.extend(required_errors)

        # Check external-secrets specific dependencies
        es_errors = validate_external_secrets_dependencies()
        errors.extend(es_errors)

        # Report results
        if errors:
            print("\n".join(errors))
            return 1
        else:
            print("✅ All dependency validations passed!")
            return 0

    except Exception as e:
        print(f"❌ Validation failed with error: {e}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
