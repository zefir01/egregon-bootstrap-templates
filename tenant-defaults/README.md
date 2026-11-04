# tenant-defaults

Source of the `tenant-defaults` ClusterTemplate of Egregon. The Egregon Tenant-controller creates that ClusterTemplate and a
standalone ClusterTemplateRun of the same name in every customer Workspace; the Template-controller renders `main.jsonnet`
and is the only writer of the outputs. Nothing in this repository is secret.

`main.jsonnet` has no parameters and no external variables. Names are part of the shipped profile; no UID, slug or other
value of a live Tenant is used. All outputs are cluster-scoped inside the Workspace of the Run.
The bundled `../libs/egregon.libsonnet` builds Egregon resources and grants using `k8s.libsonnet`.

| Kind | Name | Content |
| --- | --- | --- |
| `ClusterBucket` | `files` | `presigned_url.max_ttl: 24h`, `versioning.status: Enabled`, `object_lock.enabled: false`; no lifecycle expiration, everything else is the Bucket contract default |
| `ClusterRole` | `files-bucket-data-access` | `egregon.ai` / `clusterbuckets`, `resourceNames: [files]`, verbs exactly `get`, `list_objects`, `get_object`, `get_object_version`, `put_object` |
| `ClusterRoleBinding` | `files-bucket-data-access` | group `system:authenticated` → that role |
| `ClusterRole` | `skills-mcp-access` | `egregon.ai` / `clustermcps`, `resourceNames: [skills]`, verbs exactly `get`, `list_skills`, `read_skill` |
| `ClusterRoleBinding` | `skills-mcp-access` | group `system:authenticated` → that role |

The ClusterMcp `skills` itself is not an output: the Skills-controller creates it. The roles have no wildcard, no delete or version-history verbs, no bucket CRUD and no Workspace entry grant (`access /`).
Sync waves: role `-2`, binding `-1`, bucket `0`.

Test (needs `jsonnet` on `PATH`): `python3 -m unittest discover -s tests`.
