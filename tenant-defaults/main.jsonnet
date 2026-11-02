// Base resources of every Egregon Tenant, rendered by the ClusterTemplateRun `tenant-defaults` that the Tenant-controller
// creates in each customer Workspace. All outputs are cluster-scoped inside that Workspace. The file takes no parameters and
// no external variables: the names are part of the shipped profile (Agent templates refer to the bucket as ClusterBucket
// `files`), and no UID or tenant value is used.
local bucketName = 'files';
local accessName = 'files-bucket-data-access';
local skillsMcpAccessName = 'skills-mcp-access';
local wave(n) = { 'egregon.ai/sync-wave': n };
[
  {
    apiVersion: 'rbac.authorization.k8s.io/v1',
    kind: 'ClusterRole',
    metadata: { name: accessName, annotations: wave('-2') },
    // Object data of this one bucket, without delete, version history, multipart administration or any bucket CRUD.
    rules: [{
      apiGroups: ['egregon.ai'],
      resources: ['clusterbuckets'],
      resourceNames: [bucketName],
      verbs: ['get', 'list_objects', 'get_object', 'get_object_version', 'put_object'],
    }],
  },
  {
    apiVersion: 'rbac.authorization.k8s.io/v1',
    kind: 'ClusterRoleBinding',
    metadata: { name: accessName, annotations: wave('-1') },
    roleRef: { apiGroup: 'rbac.authorization.k8s.io', kind: 'ClusterRole', name: accessName },
    subjects: [{ apiGroup: 'rbac.authorization.k8s.io', kind: 'Group', name: 'system:authenticated' }],
  },
  {
    apiVersion: 'rbac.authorization.k8s.io/v1',
    kind: 'ClusterRole',
    metadata: { name: skillsMcpAccessName, annotations: wave('-2') },
    // Use of the shared ClusterMcp `skills` (served by the Skills-controller); no ClusterMcp CRUD.
    rules: [{
      apiGroups: ['egregon.ai'],
      resources: ['clustermcps'],
      resourceNames: ['skills'],
      verbs: ['get', 'list_skills', 'read_skill'],
    }],
  },
  {
    apiVersion: 'rbac.authorization.k8s.io/v1',
    kind: 'ClusterRoleBinding',
    metadata: { name: skillsMcpAccessName, annotations: wave('-1') },
    roleRef: { apiGroup: 'rbac.authorization.k8s.io', kind: 'ClusterRole', name: skillsMcpAccessName },
    subjects: [{ apiGroup: 'rbac.authorization.k8s.io', kind: 'Group', name: 'system:authenticated' }],
  },
  {
    apiVersion: 'egregon.ai/v1alpha1',
    kind: 'ClusterBucket',
    metadata: { name: bucketName, annotations: wave('0') },
    // No lifecycle expiration: stored history has no hidden retention period. Everything not stated here keeps the
    // Bucket contract of Egregon.
    spec: {
      presigned_url: { max_ttl: '24h' },
      versioning: { status: 'Enabled' },
      object_lock: { enabled: false },
    },
  },
]
