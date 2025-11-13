#!/usr/bin/env python3
"""
Talos cluster Stage 1 health check - validates infrastructure before Flux deployment.
Tests basic connectivity, APIs, and cluster access without requiring CNI.
"""

import asyncio
import json
import sys
import traceback
from dataclasses import dataclass, field
from enum import StrEnum
from pathlib import Path
from typing import Dict, List, Optional, Tuple

import aiohttp
from kubernetes import client, config
from kubernetes.client.exceptions import ApiException
from rich.console import Console, Group
from rich.live import Live
from rich.panel import Panel
from rich.table import Table
from rich.text import Text


class TestStatus(StrEnum):
    """Test status without emojis"""

    PENDING = "pending"
    PASS = "pass"
    FAIL = "fail"
    SKIP = "skip"


@dataclass
class TestResult:
    """Result of a test with optional error details"""

    status: TestStatus
    error: Optional[str] = None


def format_status(result: Optional[TestResult]) -> str:
    """Convert status to display text"""
    if not result or result.status == TestStatus.PENDING:
        return "[yellow]PENDING[/yellow]"
    elif result.status == TestStatus.PASS:
        return "[green]PASS[/green]"
    elif result.status == TestStatus.SKIP:
        return "[dim]SKIP[/dim]"
    elif result.status == TestStatus.FAIL:
        error_text = f" ({result.error})" if result.error else ""
        return f"[red]FAIL[/red]{error_text}"
    return "[red]UNKNOWN[/red]"


@dataclass
class ClusterConfig:
    """Terraform-extracted cluster configuration"""

    controllers: List[str]
    workers: List[str]
    all_nodes: List[str]
    vip: str
    api_port: int


@dataclass
class NodeTests:
    """Test results for a single node"""

    node: str
    node_type: str
    talos_api: TestResult = field(
        default_factory=lambda: TestResult(TestStatus.PENDING)
    )
    kube_api: TestResult = field(default_factory=lambda: TestResult(TestStatus.PENDING))


@dataclass
class ClusterTests:
    """Test results for cluster-level checks"""

    vip_ping: TestResult = field(default_factory=lambda: TestResult(TestStatus.PENDING))
    vip_kube_api: TestResult = field(
        default_factory=lambda: TestResult(TestStatus.PENDING)
    )
    nodes_exist: TestResult = field(
        default_factory=lambda: TestResult(TestStatus.PENDING)
    )
    kubectl_access: TestResult = field(
        default_factory=lambda: TestResult(TestStatus.PENDING)
    )


class Stage1HealthChecker:
    """Stage 1 (pre-Flux) cluster health checker"""

    def __init__(self):
        self.console = Console()
        self.config: Optional[ClusterConfig] = None
        self.node_tests: Dict[str, NodeTests] = {}
        self.cluster_tests = ClusterTests()

    async def run_cmd(
        self, cmd: List[str], timeout_sec: float = 30
    ) -> Tuple[bool, str, str]:
        """Run command and return (success, stdout, stderr)"""
        try:
            proc = await asyncio.create_subprocess_exec(
                *cmd,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE,
                cwd=Path(__file__).parent,
            )
            stdout, stderr = await asyncio.wait_for(
                proc.communicate(), timeout=timeout_sec
            )
            return proc.returncode == 0, stdout.decode(), stderr.decode()
        except asyncio.TimeoutError:
            return False, "", f"Timeout after {timeout_sec}s"
        except Exception as e:
            return False, "", str(e)

    async def load_config(self) -> ClusterConfig:
        """Load configuration from terraform outputs"""
        outputs = ["controllers", "workers", "all_nodes", "cluster_config"]
        tasks = [
            self.run_cmd(["terraform", "output", "-json", output]) for output in outputs
        ]
        results = await asyncio.gather(*tasks)

        data = {}
        for output, (success, stdout, stderr) in zip(outputs, results):
            if not success:
                raise RuntimeError(f"Failed to get {output}: {stderr}")
            data[output] = json.loads(stdout)

        cluster_config = data["cluster_config"]
        all_nodes = [node["ip_address"] for node in data["all_nodes"].values()]

        config = ClusterConfig(
            controllers=data["controllers"],
            workers=data["workers"],
            all_nodes=all_nodes,
            vip=cluster_config["vip"],
            api_port=cluster_config["api_port"],
        )

        # Initialize node tests
        for node in config.all_nodes:
            node_type = "controller" if node in config.controllers else "worker"
            self.node_tests[node] = NodeTests(node=node, node_type=node_type)

        return config

    async def test_talos_api(self, node: str) -> TestResult:
        """Test Talos API endpoint using talosctl (config via direnv)"""
        try:
            success, _, stderr = await self.run_cmd(
                ["talosctl", "version", "--endpoints", node, "--nodes", node],
                timeout_sec=10,
            )

            return TestResult(
                TestStatus.PASS if success else TestStatus.FAIL,
                stderr.strip() if not success else None,
            )
        except Exception as e:
            return TestResult(TestStatus.FAIL, str(e))

    async def test_kube_api(self, node: str) -> TestResult:
        """Test Kubernetes API endpoint (controllers only)"""
        url = f"https://{node}:{self.config.api_port}/version"

        try:
            timeout = aiohttp.ClientTimeout(connect=5, total=10)
            async with aiohttp.ClientSession(
                timeout=timeout, connector=aiohttp.TCPConnector(ssl=False)
            ) as session:
                async with session.get(url) as response:
                    # 200 = OK, 401 = Unauthorized (but API is responding)
                    # 403 = Forbidden (but API is responding)
                    if response.status in (200, 401, 403):
                        return TestResult(TestStatus.PASS)
                    else:
                        return TestResult(TestStatus.FAIL, f"HTTP {response.status}")
        except Exception as e:
            return TestResult(TestStatus.FAIL, str(e))

    async def test_kubectl_access(self) -> TestResult:
        """Test Kubernetes API access using Python client with kubeconfig"""
        try:
            # Load kubeconfig from current directory (written by terraform)
            kubeconfig_path = Path(__file__).parent / "kubeconfig"
            if not kubeconfig_path.exists():
                return TestResult(TestStatus.FAIL, "kubeconfig not found")

            # Load the kubeconfig
            config.load_kube_config(config_file=str(kubeconfig_path))

            # Create API client and test connection
            v1 = client.CoreV1Api()

            # Run in executor to avoid blocking
            loop = asyncio.get_event_loop()
            await loop.run_in_executor(None, v1.list_node)

            return TestResult(TestStatus.PASS)

        except ApiException as e:
            return TestResult(
                TestStatus.FAIL, f"Kubernetes API error: {e.status} {e.reason}"
            )
        except Exception as e:
            return TestResult(TestStatus.FAIL, str(e))

    async def test_nodes_exist(self) -> TestResult:
        """Check that nodes are registered in cluster"""
        success, stdout, stderr = await self.run_cmd(
            ["kubectl", "get", "nodes", "--no-headers"], timeout_sec=10
        )

        if not success:
            return TestResult(TestStatus.FAIL, stderr.strip())

        if not stdout.strip():
            return TestResult(TestStatus.FAIL, "No nodes found")

        return TestResult(TestStatus.PASS)

    async def test_node_complete(self, node: str) -> None:
        """Run all tests for a single node"""
        node_test = self.node_tests[node]

        # Test Talos API and Kubernetes API independently
        node_test.talos_api = await self.test_talos_api(node)

        if node_test.node_type == "controller":
            node_test.kube_api = await self.test_kube_api(node)
        else:
            node_test.kube_api = TestResult(TestStatus.SKIP, "Worker node")

    def create_display(self) -> Panel:
        """Create Rich display panel"""
        if not self.config:
            return Panel("Loading configuration...", title="Stage 1 Health Check")

        # Node tests table
        node_table = Table(show_header=True)
        node_table.add_column("Node", style="cyan")
        node_table.add_column("Type", style="magenta")
        node_table.add_column("Talos API")
        node_table.add_column("Kube API")

        for node in self.config.all_nodes:
            tests = self.node_tests[node]
            node_table.add_row(
                node,
                tests.node_type,
                format_status(tests.talos_api),
                format_status(tests.kube_api),
            )

        # VIP tests table
        vip_table = Table(show_header=True)
        vip_table.add_column("VIP Test", style="cyan")
        vip_table.add_column("Status")

        vip_table.add_row("Talos API", format_status(self.cluster_tests.vip_ping))
        vip_table.add_row("Kube API", format_status(self.cluster_tests.vip_kube_api))

        # Cluster tests table
        cluster_table = Table(show_header=True)
        cluster_table.add_column("Cluster Test", style="cyan")
        cluster_table.add_column("Status")

        cluster_table.add_row(
            "kubectl Access", format_status(self.cluster_tests.kubectl_access)
        )
        cluster_table.add_row(
            "Nodes Exist", format_status(self.cluster_tests.nodes_exist)
        )

        content = Group(
            Text("Node Connectivity", style="bold blue"),
            node_table,
            Text(""),
            Text(f"VIP ({self.config.vip}) Tests", style="bold green"),
            vip_table,
            Text(""),
            Text("Cluster Access", style="bold yellow"),
            cluster_table,
        )

        return Panel(
            content, title="🚀 Stage 1 Health Check (Pre-Flux)", border_style="blue"
        )

    async def run_all_tests(self) -> bool:
        """Run all health checks"""
        try:
            with Live(
                self.create_display(), refresh_per_second=2, console=self.console
            ) as live:
                # Load config
                self.config = await self.load_config()
                live.update(self.create_display())

                # Test all nodes in parallel
                node_tasks = [
                    self.test_node_complete(node) for node in self.config.all_nodes
                ]

                # Test VIP
                async def test_vip():
                    # Test VIP Talos and Kube APIs independently
                    self.cluster_tests.vip_ping = await self.test_talos_api(
                        self.config.vip
                    )
                    self.cluster_tests.vip_kube_api = await self.test_kube_api(
                        self.config.vip
                    )

                # Test cluster access
                async def test_cluster():
                    self.cluster_tests.kubectl_access = await self.test_kubectl_access()
                    self.cluster_tests.nodes_exist = await self.test_nodes_exist()

                # Run everything in parallel
                await asyncio.gather(*node_tasks, test_vip(), test_cluster())
                live.update(self.create_display())

                # Check if all critical tests passed
                all_pass = all(
                    [
                        # Node connectivity
                        all(
                            tests.talos_api.status == TestStatus.PASS
                            for tests in self.node_tests.values()
                        ),
                        # Controller Kube APIs
                        all(
                            tests.kube_api.status == TestStatus.PASS
                            for tests in self.node_tests.values()
                            if tests.node_type == "controller"
                        ),
                        # VIP and cluster access
                        self.cluster_tests.vip_ping.status == TestStatus.PASS,
                        self.cluster_tests.vip_kube_api.status == TestStatus.PASS,
                        self.cluster_tests.kubectl_access.status == TestStatus.PASS,
                        self.cluster_tests.nodes_exist.status == TestStatus.PASS,
                    ]
                )

                return all_pass

        except Exception as e:
            self.console.print(f"[red]Health check failed: {e}[/red]")
            traceback.print_exc()
            return False


async def main():
    checker = Stage1HealthChecker()
    success = await checker.run_all_tests()

    if success:
        print("🎉 Stage 1 health checks PASSED")
        print("✨ Cluster ready for Flux bootstrap!")
        print("Next: flux bootstrap github --owner=... --repository=... --path=k8s")
    else:
        print("❌ Stage 1 health checks FAILED")
        print("Fix connectivity issues before proceeding")

    sys.exit(0 if success else 1)


if __name__ == "__main__":
    asyncio.run(main())
