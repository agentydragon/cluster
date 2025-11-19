# Persistent AI Agents Platform Plan

## Vision

Deploy long-running AI agents with their own persistent computing resources (storage, credentials, isolated
environments) where agents can execute arbitrary long-running tasks with full computer control capabilities.

## Architecture Overview

```text
┌─────────────────────────────────────────────────────────┐
│ Chat UI (Kagent or LibreChat)                           │
│  - User conversations with agents                       │
│  - Multi-agent support                                  │
│  - Session persistence                                  │
└────────────────────┬────────────────────────────────────┘
                     │ Queries LLM (OpenAI/Anthropic)
                     │ LLM decides to use tools
                     ▼
┌─────────────────────────────────────────────────────────┐
│ Kagent Agent (Deployment)                               │
│  - Agent CRD with system prompt                         │
│  - Orchestrates tool calls                              │
│  - References MCP servers                               │
└────────────────────┬────────────────────────────────────┘
                     │ MCP Protocol
                     ▼
┌─────────────────────────────────────────────────────────┐
│ MCP Server (Deployment)                                 │
│  - computer-control-mcp (AB498)                         │
│  - Atomic tools: screenshot, click, type, key_press     │
│  - Connects to agent's desktop via X11                  │
└────────────────────┬────────────────────────────────────┘
                     │ X11 Display / VNC
                     ▼
┌─────────────────────────────────────────────────────────┐
│ Agent's Private Desktop (Pod with PVC)                  │
│  - Persistent 20Gi workspace                            │
│  - VNC server (optional monitoring)                     │
│  - Desktop environment                                  │
│  - Agent's credentials (Gitea, Harbor, etc.)            │
│  - Development tools                                    │
└─────────────────────────────────────────────────────────┘
```

## Component Breakdown

### 1. Chat Interface

**Options:**

- **Kagent UI** (built-in, per-agent chat with sessions)
- **LibreChat** (more features, OIDC support, multi-model)
- **Open WebUI** (lightweight alternative)

**Recommendation:** Start with Kagent UI (comes with the platform)

### 2. Agent Orchestration (Kagent)

**Kagent Agent CRD:**

```yaml
apiVersion: kagent.dev/v1alpha2
kind: Agent
metadata:
  name: devbot
  namespace: agents
spec:
  type: Declarative
  description: "Development assistant with full computer control"

  declarative:
    systemMessage: |
      You are DevBot, a development assistant with access to your own Linux desktop.
      You can use these capabilities:
      - Take screenshots to see the current state
      - Click on UI elements
      - Type text and press keys
      - Execute shell commands
      - Clone repos, run tests, debug issues

      Your workspace is persistent at /home/agent/workspace.
      You have credentials pre-configured for:
      - Gitea: git.test-cluster.agentydragon.com
      - Harbor: registry.test-cluster.agentydragon.com

    modelConfig: anthropic-claude

    tools:
      - type: McpServer
        mcpServer:
          name: devbot-computer-control
          kind: RemoteMCPServer
          apiGroup: kagent.dev
          toolNames:
            - screenshot
            - mouse_click
            - mouse_move
            - type_text
            - press_key
            - key_down
            - key_up
            - get_screen_size

    deployment:
      replicas: 1
      env:
        - name: ANTHROPIC_API_KEY
          valueFrom:
            secretKeyRef:
              name: devbot-secrets
              key: anthropic-key
      resources:
        requests:
          cpu: "500m"
          memory: "1Gi"
```

**Key Features:**

- Agents defined as K8s CRDs
- Tools via MCP protocol only (no other options)
- Can reference other agents as tools
- Deployment spec embedded (volumes, env, resources)

### 3. MCP Server (computer-control-mcp)

**Selected:** `computer-control-mcp` by AB498

**Why:**

- ✅ Most complete tool set (mouse, keyboard, screen, OCR, window management)
- ✅ Python-based (easy to containerize)
- ✅ No size limitations (unlike tanob's 1MB screenshot limit)
- ✅ Docker support included
- ✅ MIT licensed
- ✅ Cross-platform (Linux/Windows/macOS)

**Repository:** <https://github.com/AB498/computer-control-mcp>

**Tools Provided:**

- `screenshot` - Capture screen
- `mouse_click(x, y, button, clicks)` - Click at coordinates
- `mouse_move(x, y)` - Move cursor
- `mouse_down(button)` / `mouse_up(button)` - Hold/release
- `drag_mouse(x1, y1, x2, y2)` - Drag operation
- `type_text(text)` - Type at cursor
- `press_key(key)` - Press individual keys
- `key_down(key)` / `key_up(key)` - Hold/release keys
- `ocr_screenshot()` - Extract text with coordinates
- `get_screen_size()` - Display resolution
- Window management tools

**Deployment:**

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: devbot-mcp-server
  namespace: agents
spec:
  replicas: 1
  selector:
    matchLabels:
      app: devbot-mcp
      agent: devbot
  template:
    metadata:
      labels:
        app: devbot-mcp
        agent: devbot
    spec:
      containers:
      - name: mcp-server
        image: computer-control-mcp:latest
        env:
        - name: DISPLAY
          value: "devbot-desktop:0"  # Connect to desktop's X11
        - name: MCP_TRANSPORT
          value: "sse"  # Server-Sent Events for K8s
        - name: MCP_PORT
          value: "8080"
        ports:
        - name: mcp
          containerPort: 8080
        resources:
          requests:
            cpu: "250m"
            memory: "512Mi"
---
apiVersion: v1
kind: Service
metadata:
  name: devbot-mcp
  namespace: agents
spec:
  selector:
    app: devbot-mcp
    agent: devbot
  ports:
  - name: mcp
    port: 8080
    targetPort: 8080
```

### 4. Agent's Private Desktop

**Current Plan:** Simple Pod with PVC (not StatefulSet)

**⚠️ Known Limitation:**

- Pod restarts = potential data loss for in-memory state
- Workspace files persist (PVC), but running processes don't
- **Trade-off:** Simpler to start with, can upgrade to StatefulSet later

**Deployment:**

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: devbot-desktop
  namespace: agents
spec:
  replicas: 1
  selector:
    matchLabels:
      app: devbot-desktop
      agent: devbot
  template:
    metadata:
      labels:
        app: devbot-desktop
        agent: devbot
    spec:
      initContainers:
      - name: setup-credentials
        image: busybox
        command: ["/bin/sh", "-c"]
        args:
          - |
            # Setup git credentials
            mkdir -p /workspace/.config/git
            cat > /workspace/.config/git/config <<EOF
            [user]
              name = DevBot
              email = devbot@agents.local
            [credential]
              helper = store
            EOF

            cat > /workspace/.config/git/credentials <<EOF
            https://devbot:${GITEA_TOKEN}@git.test-cluster.agentydragon.com
            EOF
            chmod 600 /workspace/.config/git/credentials
        env:
        - name: GITEA_TOKEN
          valueFrom:
            secretKeyRef:
              name: devbot-credentials
              key: gitea-token
        volumeMounts:
        - name: workspace
          mountPath: /workspace

      containers:
      - name: desktop
        image: devbot-desktop:latest  # Custom image (see below)
        env:
        - name: VNC_PASSWORD
          valueFrom:
            secretKeyRef:
              name: devbot-credentials
              key: vnc-password
        - name: DISPLAY
          value: ":0"
        ports:
        - name: vnc
          containerPort: 5900
        - name: x11
          containerPort: 6000
        volumeMounts:
        - name: workspace
          mountPath: /home/agent/workspace
        - name: config
          mountPath: /home/agent/.config
        resources:
          requests:
            cpu: "1"
            memory: "2Gi"
          limits:
            cpu: "2"
            memory: "4Gi"

      volumes:
      - name: workspace
        persistentVolumeClaim:
          claimName: devbot-workspace
      - name: config
        persistentVolumeClaim:
          claimName: devbot-config
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: devbot-workspace
  namespace: agents
spec:
  storageClassName: proxmox-csi
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 20Gi
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: devbot-config
  namespace: agents
spec:
  storageClassName: proxmox-csi
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 5Gi
---
apiVersion: v1
kind: Service
metadata:
  name: devbot-desktop
  namespace: agents
spec:
  selector:
    app: devbot-desktop
    agent: devbot
  ports:
  - name: vnc
    port: 5900
    targetPort: 5900
  - name: x11
    port: 6000
    targetPort: 6000
```

**Desktop Image (`devbot-desktop:latest`):**

```dockerfile
FROM ubuntu:22.04

# Install desktop environment
RUN apt-get update && apt-get install -y \
    xfce4 xfce4-terminal \
    tigervnc-standalone-server \
    dbus-x11 \
    firefox \
    git curl wget \
    python3 python3-pip \
    nodejs npm \
    build-essential \
    vim nano \
    && rm -rf /var/lib/apt/lists/*

# Create agent user
RUN useradd -m -s /bin/bash agent && \
    echo "agent ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

# VNC setup
USER agent
WORKDIR /home/agent

# VNC password and xstartup
RUN mkdir -p ~/.vnc && \
    echo '#!/bin/bash\nstartxfce4 &' > ~/.vnc/xstartup && \
    chmod +x ~/.vnc/xstartup

# Startup script
COPY --chown=agent:agent start-desktop.sh /home/agent/
RUN chmod +x /home/agent/start-desktop.sh

EXPOSE 5900 6000

CMD ["/home/agent/start-desktop.sh"]
```

**start-desktop.sh:**

```bash
#!/bin/bash

# Set VNC password from env
echo "${VNC_PASSWORD:-password}" | vncpasswd -f > ~/.vnc/passwd
chmod 600 ~/.vnc/passwd

# Start VNC server
vncserver :0 -geometry 1920x1080 -depth 24 -localhost no

# Keep container running
tail -f ~/.vnc/*.log
```

### 5. Credentials Management (ESO)

**ExternalSecret for per-agent credentials:**

```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: devbot-credentials
  namespace: agents
spec:
  refreshInterval: 8760h  # 1 year (avoid rotation issues)
  secretStoreRef:
    name: vault-backend
    kind: ClusterSecretStore
  target:
    name: devbot-credentials
  data:
    - secretKey: anthropic-key
      remoteRef:
        key: secret/agents/devbot
        property: anthropic-key
    - secretKey: gitea-token
      remoteRef:
        key: secret/agents/devbot
        property: gitea-token
    - secretKey: harbor-password
      remoteRef:
        key: secret/agents/devbot
        property: harbor-password
    - secretKey: vnc-password
      remoteRef:
        key: secret/agents/devbot
        property: vnc-password
```

## CLI-Only Prototype (No Visual Capabilities)

**Simpler First Step:** Start without desktop/VNC, just shell access

**Benefits:**

- No X11/VNC complexity
- Faster to prototype
- Still fully functional for CLI tasks
- Can add visual capabilities later

**Architecture:**

```text
Kagent Agent → MCP Server (shell tools) → Agent Container (bash shell)
```

**MCP Server for CLI:**

- Use simple exec-based MCP server
- Tools: `run_command`, `read_file`, `write_file`, `list_directory`
- No desktop environment needed

**Agent Container (Simplified):**

```dockerfile
FROM ubuntu:22.04

RUN apt-get update && apt-get install -y \
    git curl wget \
    python3 python3-pip \
    nodejs npm \
    build-essential \
    && rm -rf /var/lib/apt/lists/*

# Agent user
RUN useradd -m -s /bin/bash agent
USER agent
WORKDIR /home/agent

CMD ["sleep", "infinity"]
```

**Upgrade Path:**

1. **Phase 1:** CLI-only agent (prove persistence, credentials, MCP integration)
2. **Phase 2:** Add desktop + computer-control-mcp (full visual capabilities)

## Helm Chart Structure

**Per-Agent Helm Chart:**

```text
charts/kagent-agent/
├── Chart.yaml
├── values.yaml
├── templates/
│   ├── agent.yaml              # Kagent Agent CRD
│   ├── mcp-deployment.yaml     # MCP server
│   ├── mcp-service.yaml        # MCP server service
│   ├── desktop-deployment.yaml # Agent's desktop/shell
│   ├── desktop-service.yaml    # Desktop services
│   ├── pvcs.yaml               # Persistent volumes
│   ├── externalsecret.yaml     # ESO credentials
│   └── _helpers.tpl            # Template helpers
```

**values.yaml:**

```yaml
agent:
  name: devbot
  namespace: agents
  systemMessage: "You are DevBot..."
  modelConfig: anthropic-claude

  # Visual capabilities
  desktop:
    enabled: true  # false for CLI-only
    image: devbot-desktop:latest
    storage:
      workspace: 20Gi
      config: 5Gi

  # MCP server
  mcp:
    image: computer-control-mcp:latest  # or custom CLI MCP server
    type: visual  # or 'cli'

  # Credentials from Vault
  credentials:
    vault:
      path: secret/agents/devbot
    gitea:
      enabled: true
    harbor:
      enabled: true

resources:
  agent:
    requests:
      cpu: "500m"
      memory: "1Gi"
  desktop:
    requests:
      cpu: "1"
      memory: "2Gi"
    limits:
      cpu: "2"
      memory: "4Gi"
  mcp:
    requests:
      cpu: "250m"
      memory: "512Mi"
```

**Deploy multiple agents:**

```bash
# Agent 1: DevBot with desktop
helm install devbot ./charts/kagent-agent \
  --set agent.name=devbot \
  --set agent.systemMessage="You are a development assistant..." \
  --set agent.desktop.enabled=true

# Agent 2: DataBot CLI-only
helm install databot ./charts/kagent-agent \
  --set agent.name=databot \
  --set agent.systemMessage="You are a data analysis assistant..." \
  --set agent.desktop.enabled=false \
  --set agent.mcp.type=cli
```

## Implementation Phases

### Phase 0: Research & Planning ✅

- [x] Research Kagent architecture
- [x] Find MCP servers with atomic computer control
- [x] Design architecture
- [x] Document plan

### Phase 1: CLI-Only Prototype

- [ ] Deploy Kagent on cluster
- [ ] Create simple exec-based MCP server
- [ ] Build agent container (CLI, no desktop)
- [ ] Deploy single agent with persistent storage
- [ ] Test: Agent clones repo, runs commands, persists workspace
- [ ] Validate credentials injection works
- [ ] Test agent restart (verify workspace persistence)

### Phase 2: Add Visual Capabilities

- [ ] Clone computer-control-mcp repository
- [ ] Build desktop container image (Ubuntu + Xfce + VNC)
- [ ] Containerize computer-control-mcp as MCP server
- [ ] Deploy agent with desktop + MCP server
- [ ] Test: Agent takes screenshots, clicks, types
- [ ] Validate X11 connectivity between MCP server and desktop

### Phase 3: Multi-Agent Support

- [ ] Create Helm chart template
- [ ] Deploy 2-3 agents with different purposes
- [ ] Test agent isolation (network policies)
- [ ] Validate per-agent credentials work
- [ ] Test concurrent agent operations

### Phase 4: Production Hardening

- [ ] Add monitoring (Prometheus metrics)
- [ ] Add logging (Loki integration)
- [ ] Network policies (agent isolation)
- [ ] Resource quotas per agent
- [ ] Backup strategy for agent workspaces
- [ ] Document operational procedures

## Future Enhancements (Bookmarked)

### Multi-Agent Orchestration (CrewAI)

**When:** After single-agent architecture is proven
**Why:** Complex tasks requiring collaboration between specialized agents
**What:** Kagent supports CrewAI integration for multi-agent workflows
**Reference:** <https://github.com/kagent-dev/kagent/tree/main/python/packages/kagent-crewai>
**Features:**

- Agent crews with defined roles (researcher, writer, analyst)
- Task delegation between agents
- Hierarchical agent structures
- Shared context and memory
**Use Cases:**
- Research crew (searcher + analyzer + writer)
- DevOps crew (planner + implementer + tester)
- Complex workflows requiring specialized expertise per step

### OpenTelemetry Integration

**When:** After agents are deployed in production
**Why:** Trace agent tool calls, observe decision paths, debug failures
**What:** Add OpenTelemetry to cluster + Kagent agent traces
**Benefits:**

- Trace agent → LLM → tool call chains
- Visualize agent reasoning paths
- Identify bottlenecks (slow tools, LLM latency)
- Debug multi-agent coordination
- Performance optimization data
**Implementation:**
- Deploy OpenTelemetry Collector in cluster
- Configure Kagent agents with OTEL exporters
- Jaeger or Tempo for trace storage
- Grafana for visualization
**Integration:** Ties into cluster observability stack (Prometheus, Loki, Grafana)
**Reference:** docs/PLAN.md observability section

### Agent Sandbox Integration

**When:** After basic architecture is stable
**Why:** Stronger isolation, pre-warmed pools, sub-second cold starts
**What:** Replace Deployment with Agent Sandbox CRD
**Reference:** kubernetes-sigs/agent-sandbox

### StatefulSet for Desktop

**When:** If pod restart data loss becomes problematic
**Why:** Stable pod identity, ordered deployment
**What:** Change desktop Deployment → StatefulSet
**Trade-off:** More complexity, slower rollouts

### Proxmox VM Backend

**When:** If K8s pods prove insufficient for isolation
**Why:** Full VM isolation, traditional desktop environment
**What:** Terraform-managed VMs, MCP server in K8s connects to VMs
**Trade-off:** Higher resource usage, slower provisioning

### Guacamole Integration

**When:** Need web-based monitoring/debugging of agent desktops
**Why:** View agent desktop in browser without VNC client
**What:** Deploy Guacamole + Authentik RAC
**Reference:** docs/PLAN.md Guacamole section

## Known Limitations & Trade-offs

### Current Architecture

#### Desktop Pod Restart = Process Loss

- Workspace files persist (PVC)
- Running processes do NOT persist
- In-memory state lost
- **Impact:** Long-running compilations, downloads interrupted
- **Mitigation:** Agent can detect and restart tasks
- **Future:** Upgrade to StatefulSet or CRIU checkpointing

#### No Visual Session Persistence

- Desktop environment resets on restart
- Open windows/applications lost
- **Impact:** Manual window arrangements not saved
- **Mitigation:** Agent can re-launch applications via MCP tools

#### Single MCP Transport

- Kagent only supports MCP protocol (no HTTP tools, no direct exec)
- **Impact:** All computer control must go through MCP server
- **Mitigation:** MCP is flexible, can wrap any capability

#### Resource Overhead

- Each agent = 3 pods (Agent + MCP + Desktop)
- Each agent = ~3.75 CPU cores + ~7.5Gi RAM (with desktop)
- **Impact:** Limited agents per cluster
- **Current capacity:** 5 agents max on current cluster
- **Mitigation:** CLI-only agents use ~1.75 CPU + 3.5Gi RAM

### Kagent Tool Limitations

**Only 2 Tool Types:**

1. **McpServer** - MCP protocol only
2. **Agent** - Other agents as tools

**No support for:**

- ❌ HTTP/REST tools
- ❌ Direct exec/subprocess
- ❌ Native Python functions
- ❌ OpenAPI integration (unless via MCP proxy)

**Workaround:** Create custom MCP servers to wrap any capability

## References

### Code Repositories

- **Kagent:** `/code/github.com/kagent-dev/kagent`
- **vnc-use:** `/code/github.com/mayflower/vnc-use`
- **computer-control-mcp:** (TODO: clone)
- **Anthropic quickstarts:** (TODO: clone reference patterns)

### Documentation

- **Kagent Docs:** <https://kagent.dev/docs>
- **MCP Specification:** <https://modelcontextprotocol.io>
- **Agent Sandbox:** <https://github.com/kubernetes-sigs/agent-sandbox>
- **computer-control-mcp:** <https://github.com/AB498/computer-control-mcp>

### Related PLAN.md Sections

- Guacamole + Authentik RAC (browser-based desktop access)
- Agent Sandbox future enhancement
- Rook-Ceph for RWX storage (if multiple pods need shared filesystem)

## Success Criteria

**Phase 1 Success:**

- ✅ Agent can execute shell commands persistently
- ✅ Workspace survives agent pod restart
- ✅ Credentials properly injected and functional
- ✅ Agent can clone repos, run builds, commit results

**Phase 2 Success:**

- ✅ Agent can take screenshots and see desktop state
- ✅ Agent can click UI elements by coordinates
- ✅ Agent can type text and navigate applications
- ✅ Full computer control loop works (observe → decide → act)

**Phase 3 Success:**

- ✅ Multiple agents running concurrently
- ✅ Each agent isolated (network, credentials, workspace)
- ✅ Per-agent Helm chart deployment works
- ✅ Can deploy new agent in <5 minutes

**Production Ready:**

- ✅ Monitoring and alerting configured
- ✅ Backup/restore procedures documented
- ✅ Resource quotas prevent runaway agents
- ✅ Security policies enforced (network isolation, RBAC)
- ✅ Operational runbooks created
