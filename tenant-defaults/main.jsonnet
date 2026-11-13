// Base resources of every Tenant. Names are part of the shipped profile;
// all resources belong to the customer Workspace and require no external inputs.
local egregon = import '../libs/egregon.libsonnet';

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
  // and they grant nothing on Runs: the Template-controller admits a live Run's tool only from an owner of the target Run,
  // and a hibernation archive tool only by the caller's own native patch/delete/list/get on that Run.
  egregon.permission(['clustermcps'], ['template-runs'],
                     ['get', 'patch_run', 'delete_run', 'hibernate_run', 'wake_run', 'list_hibernated_runs', 'delete_hibernated_run']),
], principal_kind='Group', wave=-2, binding_wave=-1) +
egregon.grant('mental-models-mcp-access', null, 'system:authenticated', [
  // The Tenant-controller provisions this platform MCP (spec.function mental-models, served by the Memory-controller). This is only the entry to its five tools:
  // the tools themselves review the caller's own native rights on the exact policy, source, resource and every explicit recipient (use, subscribe_mm, delete),
  // and nothing here grants any of those. Source and recipient grants are native and never shared.
  egregon.permission(['clustermcps'], ['mental-models'],
                     ['get', 'create_personal_mental_model', 'read_personal_mental_model', 'delete_personal_mental_model',
                      'create_mental_model_subscription', 'delete_mental_model_subscription']),
], principal_kind='Group', wave=-2, binding_wave=-1) + [
  // Versioned storage, no expiration policy.
  egregon.clusterBucket('files', max_url_ttl='24h', versioning='Enabled', object_lock=false),
]
