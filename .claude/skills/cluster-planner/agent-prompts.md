# Agent Prompt Templates

## Component Research Agent Prompt

```
COMPONENT RESEARCH TASK: [Component Name]

Your mission: Deep research into this Kubernetes component to understand its REAL deployment requirements, not just the marketing material.

RESEARCH METHODOLOGY:
1. Find and analyze official documentation
2. Examine Helm charts/operators if applicable
3. Study CRDs and API specifications
4. Look for gotchas in GitHub issues/discussions
5. Identify version-specific requirements
6. Map environmental dependencies (nodes, kernel, etc.)

CRITICAL QUESTIONS TO ANSWER:
- What does it need to START? (not just to work optimally)
- What does it PROVIDE to other components?
- What are its bootstrap vs runtime dependencies?
- Does it need special privileges (DaemonSet, hostNetwork, etc.)?
- What happens if dependencies are unavailable?
- Are there chicken-egg problems with other components?
- What CRDs does it create/depend on?
- What secrets/ConfigMaps does it need?
- What network policies should exist?
- What storage requirements exist?

GOTCHA DETECTION:
- Look for warnings in documentation
- Check known issues in GitHub
- Identify timing dependencies (webhooks, CRDs)
- Find privilege escalation requirements
- Discover node-level dependencies

OUTPUT FORMAT:
Provide a structured analysis:
- Dependencies: [startup vs runtime]
- Provides: [services, CRDs, etc.]
- Bootstrap method: [how to start with minimal deps]
- Deploy type: [Deployment/DaemonSet/Operator/etc.]
- Special notes: [gotchas, privileges, timing]
- Security requirements: [RBAC, secrets, network]
- Environmental needs: [node features, kernel modules]

Focus on PRACTICAL deployment reality, not theoretical documentation.
```

## Critic Agent Prompt Template

```
CRITIC REVIEW REQUEST

You are an expert Kubernetes SRE reviewing a cluster deployment plan. Your job is to find problems BEFORE they happen in production.

PLAN TO REVIEW:
Component: [name]
Proposed Dependencies: [list]
Proposed Bootstrap Method: [method]
Deployment Strategy: [approach]
Secret Management: [approach]

REVIEW FRAMEWORK:
1. DEPENDENCY ANALYSIS
   - Are all dependencies truly necessary for startup?
   - Any missing dependencies that aren't obvious?
   - Could this create circular dependencies with other components?
   - Are dependency versions compatible?

2. BOOTSTRAP REALITY CHECK
   - Can this actually start with the proposed bootstrap method?
   - Are bootstrap secrets properly secured?
   - Is there a clear path from bootstrap to production config?
   - What happens if bootstrap fails halfway through?

3. SECURITY REVIEW
   - Are secrets handled securely?
   - Is RBAC properly scoped?
   - Any privilege escalation concerns?
   - Network policy gaps?

4. OPERATIONAL CONCERNS
   - What happens if this component dies?
   - How do you debug when it's not working?
   - Are health checks meaningful?
   - Is monitoring/alerting possible?
   - Can you roll back if deployment fails?

5. INTEGRATION GOTCHAS
   - How does this interact with existing cluster components?
   - Any version conflicts with existing software?
   - Timing issues with webhooks/CRDs?
   - Resource contention possibilities?

CRITIC GUIDELINES:
- Be skeptical but constructive
- Focus on "what could go wrong?"
- Consider both technical and operational aspects
- Suggest alternatives when pointing out problems
- Think about the 3 AM debugging scenario

OUTPUT FORMAT:
VALIDATION RESULT: [PASS/NEEDS_WORK/REJECT]

ISSUES FOUND:
- [List specific concerns with severity]

SUGGESTIONS:
- [Specific actionable recommendations]

QUESTIONS TO INVESTIGATE:
- [Things that need more research]

If NEEDS_WORK or REJECT, provide clear guidance on what needs to change.
```

## Circular Dependency Analysis Prompt

```
CIRCULAR DEPENDENCY ANALYSIS TASK

You have been given a dependency graph that may contain circular dependencies. Your job is to:

1. DETECT CYCLES
   - Use graph analysis to find circular dependencies
   - Identify the shortest cycles (most problematic)
   - Map which components are involved in each cycle

2. UNDERSTAND THE CYCLE NATURE
   - Is this a startup dependency or runtime dependency cycle?
   - Can the cycle be broken with phased deployment?
   - Are there bootstrap alternatives for any components?

3. PROPOSE SOLUTIONS
   For each cycle found:
   - Bootstrap workarounds (temporary configs)
   - Dependency elimination (remove unnecessary deps)
   - Proxy/stub services (temporary placeholders)
   - Phased configuration (start minimal, upgrade later)

4. VALIDATE SOLUTIONS
   - Ensure proposed solutions don't create new cycles
   - Verify solutions are operationally feasible
   - Check that security isn't compromised

DEPENDENCY DATA:
[Provide current component dependency matrix]

OUTPUT FORMAT:
CYCLES DETECTED: [number]

FOR EACH CYCLE:
- Components involved: [list]
- Cycle type: [startup/runtime/configuration]
- Severity: [critical/high/medium/low]
- Proposed solution: [detailed approach]
- Implementation steps: [ordered list]
- Validation method: [how to verify solution works]

If no cycles found, provide validation that the dependency graph is acyclic.
```

## Integration Validation Prompt

```
INTEGRATION VALIDATION TASK

You are reviewing how a newly planned component integrates with an EXISTING Kubernetes cluster.

EXISTING CLUSTER STATE:
[Provide current cluster component list and status]

NEW COMPONENT PLAN:
Component: [name]
Dependencies: [list]
Configuration: [details]

INTEGRATION ANALYSIS:
1. COMPATIBILITY CHECK
   - Version conflicts with existing components?
   - Resource conflicts (ports, storage, etc.)?
   - Namespace conflicts or requirements?

2. DEPENDENCY SATISFACTION
   - Are all dependencies available in current cluster?
   - Are dependency versions compatible?
   - Any missing CRDs or operators needed first?

3. IMPACT ANALYSIS
   - How does adding this affect existing components?
   - Any configuration changes needed for existing services?
   - Performance impact on cluster resources?

4. DEPLOYMENT STRATEGY
   - Can this be deployed without downtime?
   - What's the rollback plan if deployment fails?
   - How to validate integration success?

OUTPUT FORMAT:
INTEGRATION STATUS: [COMPATIBLE/NEEDS_PREP/INCOMPATIBLE]

PREREQUISITES:
- [List what needs to be done before deployment]

POTENTIAL CONFLICTS:
- [List any conflicts found]

RECOMMENDED APPROACH:
- [Step-by-step integration plan]

VALIDATION TESTS:
- [How to verify successful integration]
```
