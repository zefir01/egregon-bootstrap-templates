// Base resources of every Tenant. Names are part of the shipped profile;
// all resources belong to the customer Workspace and require no external inputs.
local egregon = import '../libs/egregon.libsonnet';
local k8s = import '../libs/k8s.libsonnet';

egregon.grant('files-bucket-data-access', null, 'system:authenticated', [
  // Data access to this bucket only; no bucket CRUD, deletion or history listing.
  egregon.permission(['clusterbuckets'], ['files'],
                     ['get', 'list_objects', 'get_object', 'get_object_version', 'put_object']),
], principal_kind='Group', wave=-2, binding_wave=-1) +
egregon.grant('skills-mcp-access', null, 'system:authenticated', [
  // The Skills-controller creates this MCP; bootstrap only grants its use.
  egregon.permission(['clustermcps'], ['skills'], ['get', 'list_skills', 'read_skill']),
], principal_kind='Group', wave=-2, binding_wave=-1) +
egregon.grant('template-runs-mcp-access', null, 'system:authenticated', [
  // The Tenant-controller provisions this platform MCP; its tool verbs are not the native patch/delete of the ClusterMcp,
  // and they grant nothing on Runs: the Template-controller admits only an owner of the target Run.
  egregon.permission(['clustermcps'], ['template-runs'], ['get', 'patch_run', 'delete_run']),
], principal_kind='Group', wave=-2, binding_wave=-1) + [
  // Every right inside this Workspace and nothing outside it. No binding here: the Tenant-controller binds the first
  // human User of a new Tenant to it, and the admin-minimal template binds its Agent to it.
  k8s.cluster_role('egregon-workspace-admin', [
    { apiGroups: ['*'], resources: ['*'], verbs: ['*'] },
    { nonResourceURLs: ['*'], verbs: ['*'] },
  ]) { metadata+: { annotations: { 'egregon.ai/sync-wave': '-2' } } },
  // Versioned storage, no expiration policy.
  egregon.clusterBucket('files', max_url_ttl='24h', versioning='Enabled', object_lock=false),
]
