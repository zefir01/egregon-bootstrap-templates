// The developer telemetry MCP of a developer Workspace (docs/egregon/telemetry-developer-mcp.md in zefir01/ai-platform): the
// ClusterMcp that the platform function "telemetry-developer" of ONE Egregon instance serves, and the native rights around it.
// Operator-run, never bootstrapped into Tenants: render it for the developer Workspace only, at an exact commit. The instance
// serves this ClusterMcp only while the exact kcp logical cluster ID of this Workspace is pinned in its env.yaml
// (telemetry_developer_access); a name or a ClusterMcp of this shape in any other Workspace is never served.
//
// developer_groups: comma-separated native Group names that may use the tools (administrators/developers of this Workspace).
// There is no grant to system:authenticated and none to the members of the Workspace as such.
// bridge_user: the kcp username of the instance's telemetry-developer-mcp ServiceAccount
//   (minikube:system:serviceaccount:<instance namespace>:telemetry-developer-mcp).
local egregon = import '../libs/egregon.libsonnet';
local k8s = import '../libs/k8s.libsonnet';

local name = 'telemetry-developer';
local tools = ['list_databases', 'list_tables', 'run_query'];
local wave(n) = { metadata+: { annotations+: { 'egregon.ai/sync-wave': std.toString(n) } } };
local binding(roleName, subjects) = k8s.clusterRoleBinding(roleName, roleName, sa=null, namespace=null) + wave(-1) + { subjects: subjects };

function(developer_groups, bridge_user)
  [
    {
      apiVersion: 'egregon.ai/v1alpha1',
      kind: 'ClusterMcp',
      metadata: { name: name, annotations: { 'egregon.ai/sync-wave': '0' } },
      spec: { 'function': name },
    },
    // The use of the tools: the entry into the Workspace (an Agent principal enters only through a group that holds `access /`;
    // without it the caller sees no command at all), the entry verb of the ClusterMcp and the three tool verbs. The call is
    // authorized again per tool as the calling principal's own native right; nothing here grants any resource action.
    k8s.cluster_role('telemetry-developer-mcp-use', [
      { nonResourceURLs: ['/'], verbs: ['access'] },
      egregon.permission(['clustermcps'], [name], ['get'] + tools),
    ]) + wave(-2),
    binding('telemetry-developer-mcp-use', [
      { apiGroup: 'rbac.authorization.k8s.io', kind: 'Group', name: group }
      for group in std.split(developer_groups, ',')
    ]),
    // What the bridge process itself does in this Workspace: enter it, read and publish the catalogue of this one ClusterMcp,
    // and prove its callers (the live User list; the Agent, ClusterAgent and Sandbox of an Agent caller).
    k8s.cluster_role('telemetry-developer-mcp-bridge', [
      { nonResourceURLs: ['/'], verbs: ['access'] },
      egregon.permission(['clustermcps'], [name], ['get']),
      egregon.permission(['clustermcps/status'], [name], ['patch']),
      egregon.permission(['users'], null, ['list']),
      egregon.permission(['agents', 'clusteragents', 'sandboxes'], null, ['get']),
    ]) + wave(-2),
    binding('telemetry-developer-mcp-bridge', [
      { apiGroup: 'rbac.authorization.k8s.io', kind: 'User', name: bridge_user },
    ]),
  ]
