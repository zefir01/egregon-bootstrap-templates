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

  // Identity is deterministic before CREATE: the Agent's Sandbox runs in the execution namespace
  // sandboxes-<tenant slug>--<namespace> and federates as a User, not a Kubernetes ServiceAccount.
  principal(workspace, namespace, name)::
    'minikube:system:serviceaccount:sandboxes-' + std.substr(workspace, 5, std.length(workspace) - 5) +
    '--' + namespace + ':agent-' + name,

  sandbox(name, namespace, image, wave=0):: {
    apiVersion: 'egregon.ai/v1alpha1',
    kind: 'Sandbox',
    metadata: { name: name, namespace: namespace, annotations: { 'egregon.ai/sync-wave': std.toString(wave) } },
    spec: {
      image: image,
      resources: { requests: { cpu: '50m' }, limits: { cpu: '500m' } },
      volume_claim: { accessModes: ['ReadWriteOnce'], resources: { requests: { storage: '1Gi' } } },
    },
  },

  // route is a typed reference {kind, namespace?, name}; the default Bucket is the shared ClusterBucket `files`.
  agent(name, namespace, model, route, sandbox_name, prompts, annotations, wave=1):: {
    apiVersion: 'egregon.ai/v1alpha1',
    kind: 'Agent',
    metadata: { name: name, namespace: namespace, annotations: { 'egregon.ai/sync-wave': std.toString(wave) } + annotations },
    spec: {
      model: model,
      route: route,
      default_bucket: { kind: 'ClusterBucket', name: 'files' },
      prompts: prompts,
      sandbox: { name: sandbox_name },
      network_policy: {},
    },
  },

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

}
