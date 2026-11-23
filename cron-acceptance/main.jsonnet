// Acceptance workers of the cron-controller task: agent_count Agents (or ClusterAgents) labelled role=<role>, each with
// its own Sandbox and the Complete/Wait right on itself. The model route is a ClusterRoute of the Workspace.
// The prompt carries the marker "CRON-ACC-START agent=<agent name>" so a provider-fixture rule can script one Agent.
function(
  namespace,
  name_prefix='acc',
  role='worker',
  agent_kind='Agent',
  agent_count='1',
  autostart='true',
  model='gpt-example',
  route_name='openai-shared-pool',
)
  local workspace = std.extVar('workspace');
  assert std.startsWith(workspace, 'root:') : 'workspace must be root:<slug>, got ' + workspace;
  local slug = std.substr(workspace, 5, std.length(workspace) - 5);
  local cluster = agent_kind == 'ClusterAgent';
  local principalPrefix = 'minikube:system:serviceaccount:sandboxes-' + slug + '--' + namespace + ':';

  // The Complete right must exist before the Agent autostarts.
  local rbacWave = { 'egregon.ai/sync-wave': '-1' };
  local one(i) =
    local agentName = name_prefix + '-' + role + '-' + i;
    local sandboxName = agentName;
    local principal = principalPrefix + (if cluster then 'clusteragent-' else 'agent-') + agentName;
    local resource = if cluster then 'clusteragents' else 'agents';
    local sandbox = {
      apiVersion: 'egregon.ai/v1alpha1',
      kind: 'Sandbox',
      metadata: { name: sandboxName, namespace: namespace, annotations: { 'egregon.ai/sync-wave': '0' } },
      spec: {
        image: '10.110.153.236:5000/ai-platform/egregon-sandbox-executor:4b490a84a8998e01f7c14fee446299d8db276c84',
        resources: { limits: { cpu: '500m' }, requests: { cpu: '50m' } },
        suspend: false,
        volume_claim: { accessModes: ['ReadWriteOnce'], resources: { requests: { storage: '1Gi' } } },
      },
    };
    local agent = {
      apiVersion: 'egregon.ai/v1alpha1',
      kind: agent_kind,
      metadata: {
        name: agentName,
        [if !cluster then 'namespace']: namespace,
        labels: { role: role, 'acceptance/run': name_prefix },
        annotations: { 'egregon.ai/sync-wave': '0' },
      },
      spec: {
        model: model,
        effort: 'low',
        autostart: autostart == 'true',
        complete_protection: true,
        network_policy: {},
        route: { kind: 'ClusterRoute', name: route_name },
        sandbox: if cluster then { name: sandboxName, namespace: namespace } else { name: sandboxName },
        prompts: { '00-task': 'CRON-ACC-START agent=' + agentName + '. Do the task, then end with Complete.' },
      },
    };
    local rules = [{ apiGroups: ['egregon.ai'], resources: [resource], resourceNames: [agentName], verbs: ['Complete', 'Wait'] }];
    local subjects = [{ apiGroup: 'rbac.authorization.k8s.io', kind: 'User', name: principal }];
    [sandbox, agent] + (
      if cluster then [
        { apiVersion: 'rbac.authorization.k8s.io/v1', kind: 'ClusterRole', metadata: { name: 'complete-' + agentName, annotations: rbacWave }, rules: rules },
        {
          apiVersion: 'rbac.authorization.k8s.io/v1',
          kind: 'ClusterRoleBinding',
          metadata: { name: 'complete-' + agentName, annotations: rbacWave },
          subjects: subjects,
          roleRef: { apiGroup: 'rbac.authorization.k8s.io', kind: 'ClusterRole', name: 'complete-' + agentName },
        },
      ] else [
        { apiVersion: 'rbac.authorization.k8s.io/v1', kind: 'Role', metadata: { name: 'complete-' + agentName, namespace: namespace, annotations: rbacWave }, rules: rules },
        {
          apiVersion: 'rbac.authorization.k8s.io/v1',
          kind: 'RoleBinding',
          metadata: { name: 'complete-' + agentName, namespace: namespace, annotations: rbacWave },
          subjects: subjects,
          roleRef: { apiGroup: 'rbac.authorization.k8s.io', kind: 'Role', name: 'complete-' + agentName },
        },
      ]
    );

  std.flattenArrays([one(i) for i in std.range(1, std.parseInt(agent_count))])
