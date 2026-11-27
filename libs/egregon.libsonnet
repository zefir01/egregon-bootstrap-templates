local agentPrompts = import 'agent-prompts.libsonnet';
local k8s = import 'k8s.libsonnet';

// Bootstrap resources and capability grants. Kubernetes structure stays in k8s.libsonnet.
{
  clusterBucket(name, max_url_ttl, versioning, object_lock, wave=0):: {
    apiVersion: 'egregon.ai/v1alpha1',
    kind: 'ClusterBucket',
    metadata: { name: name, annotations: { 'egregon.ai/sync-wave': std.toString(wave) } },
    spec: {
      presigned_url: { max_ttl: max_url_ttl },
      versioning: { status: versioning },
      object_lock: { enabled: object_lock },
    },
  },

  // The native RBAC group of an AgentsGroup, for subjects[] of a RoleBinding or ClusterRoleBinding. The formula is owned by
  // services/egregon/core/agentsgroup (NativeGroupName); it needs only the full Workspace path.
  nativeGroupName(workspace, namespace, name):: 'egregon:agentsgroup:' + workspace + '/' + namespace + '/' + name,

  // agents maps a displayed alias to an Agent name of the same namespace.
  agentsGroup(name, namespace, agents, wave=1):: {
    apiVersion: 'egregon.ai/v1alpha1',
    kind: 'AgentsGroup',
    metadata: { name: name, namespace: namespace, annotations: { 'egregon.ai/sync-wave': std.toString(wave) } },
    spec: { agents: agents },
  },

  // storage=null renders no volume_claim: an ephemeral work directory in the container's writable layer, lost whenever
  // the container is re-created. storage_class_name is passed natively, so '' means no class.
  sandbox(name, namespace, image, wave=0, storage='1Gi', storage_class_name=null)::
    assert storage != null || storage_class_name == null : 'sandbox ' + name + ': storage_class_name requires storage (storage=null is ephemeral and has no volume claim)';
  {
    apiVersion: 'egregon.ai/v1alpha1',
    kind: 'Sandbox',
    metadata: { name: name, namespace: namespace, annotations: { 'egregon.ai/sync-wave': std.toString(wave) } },
    spec: {
      image: image,
      resources: { requests: { cpu: '50m' }, limits: { cpu: '500m' } },
      [if storage != null then 'volume_claim']: {
        accessModes: ['ReadWriteOnce'],
        resources: { requests: { storage: storage } },
        [if storage_class_name != null then 'storageClassName']: storage_class_name,
      },
    },
  },

  // route is a typed reference {kind, namespace?, name}; the default Bucket is the shared ClusterBucket `files`.
  // Returns the Agent's private prompt ConfigMap followed by the Agent; the Agent carries no prompt text, only the required selector of that ConfigMap.
  agent(name, namespace, model, route, sandbox_name, prompts, annotations, wave=1)::
    local bundle = agentPrompts.bundle('Agent', name, namespace, namespace, { normal: prompts }, { 'egregon.ai/sync-wave': std.toString(wave - 1) });
    bundle.config_maps + [{
      apiVersion: 'egregon.ai/v1alpha1',
      kind: 'Agent',
      metadata: { name: name, namespace: namespace, annotations: { 'egregon.ai/sync-wave': std.toString(wave) } + annotations },
      spec: {
        model: model,
        route: route,
        default_bucket: { kind: 'ClusterBucket', name: 'files' },
        prompts_selectors: bundle.selectors.normal,
        sandbox: { name: sandbox_name },
        network_policy: {},
      },
    }],

  permission(resources, names, verbs):: {
    apiGroups: ['egregon.ai'],
    resources: resources,
    [if names != null then 'resourceNames']: names,
    verbs: verbs,
  },

  // A grant is the role AND its binding. Scope follows the protected resource, not the caller.
  grant(name, namespace, principal, rules, wave=-2, binding_wave=wave, principal_kind='User'):: [
    (if namespace == null then k8s.cluster_role(name, rules)
     else k8s.role(name, rules, namespace=namespace)) {
      metadata+: { annotations: { 'egregon.ai/sync-wave': std.toString(wave) } },
    },
    // kcp sees the federated principal as a User, not a Kubernetes ServiceAccount.
    (if namespace == null then k8s.clusterRoleBinding(name, name, sa=null, namespace=null)
     else k8s.roleBinding(name, name, sa=null, namespace=namespace)) {
      metadata+: { annotations: { 'egregon.ai/sync-wave': std.toString(binding_wave) } },
      subjects: [{ apiGroup: 'rbac.authorization.k8s.io', kind: principal_kind, name: principal }],
    },
  ],

  // network_policy.external is rendered by each ready consumer template from its fixed upstream: only that peer and port.
  protocolAdapter(name, namespace, spec, wave=1):: {
    apiVersion: 'egregon.ai/v1alpha1',
    kind: 'ProtocolAdapter',
    metadata: { name: name, namespace: namespace, annotations: { 'egregon.ai/sync-wave': std.toString(wave) } },
    spec: spec,
  },

  // A Template (namespace given) or ClusterTemplate (namespace=null) whose source is a directory of this public
  // repository at an exact revision; its Jsonnet top-level arguments are the string arguments of `parameters_schema`.
  template(name, namespace, path, revision, parameters_schema, display_name):: {
    apiVersion: 'egregon.ai/v1alpha1',
    kind: if namespace == null then 'ClusterTemplate' else 'Template',
    metadata: {
      name: name,
      [if namespace != null then 'namespace']: namespace,
      annotations: { 'egregon.ai/display-name': display_name },
    },
    spec: {
      parameters_schema: parameters_schema,
      source: {
        repoURL: 'https://github.com/zefir01/egregon-bootstrap-templates.git',
        targetRevision: revision,
        path: path,
        directory: { include: 'main.jsonnet' },
      },
    },
  },

  // The closed schema of Jsonnet string top-level arguments: arguments maps an argument name to the JSON schema of its value.
  parameters(arguments, order=std.objectFields(arguments), optional=[]):: {
    '$schema': 'https://json-schema.org/draft/2020-12/schema',
    type: 'object',
    additionalProperties: false,
    required: ['directory'],
    properties: { directory: {
      type: 'object',
      additionalProperties: false,
      required: ['jsonnet'],
      properties: { jsonnet: {
        type: 'object',
        additionalProperties: false,
        required: ['tlas'],
        properties: { tlas: {
          type: 'array',
          minItems: std.length(order) - std.length(optional),
          maxItems: std.length(order),
          items: { oneOf: [{
            type: 'object',
            additionalProperties: false,
            required: ['name', 'value'],
            properties: { name: { const: arg }, value: arguments[arg], code: { const: false } },
          } for arg in order] },
          allOf: [{ contains: { properties: { name: { const: arg } }, required: ['name'] }, minContains: if std.member(optional, arg) then 0 else 1, maxContains: 1 } for arg in order],
        } },
      } },
    } },
  },
}
