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
| `ClusterRole` | `template-runs-mcp-access` | `egregon.ai` / `clustermcps`, `resourceNames: [template-runs]`, verbs exactly `get`, `patch_run`, `delete_run`, `hibernate_run`, `wake_run`, `list_hibernated_runs`, `delete_hibernated_run` |
| `ClusterRoleBinding` | `template-runs-mcp-access` | group `system:authenticated` → that role |
| `ClusterRole` | `mental-models-mcp-access` | `egregon.ai` / `clustermcps`, `resourceNames: [mental-models]`, verbs exactly `get`, `create_personal_mental_model`, `read_personal_mental_model`, `delete_personal_mental_model`, `create_mental_model_subscription`, `delete_mental_model_subscription` |
| `ClusterRoleBinding` | `mental-models-mcp-access` | group `system:authenticated` → that role |

The ClusterMcps `skills`, `template-runs` and `mental-models` themselves are not outputs: the Skills-controller and the Tenant-controller create them (`mental-models` is `spec.function: mental-models`, served by the Memory-controller). The `template-runs` tool verbs are not the native `patch`/`delete` of the ClusterMcp, and they give no right on any Run: for `patch_run`/`delete_run` of a live Run by name the Template-controller admits only a direct Agent/ClusterAgent owner of the target Run; for `hibernate_run`, `wake_run`, `list_hibernated_runs`, `delete_hibernated_run` and the `run_id` forms of `patch_run`/`delete_run` it asks the caller's own native `patch`, `delete`, `list` or `get` on that Run, so those grants stay separate and native. The `mental-models` verbs are tool entry only: they grant nothing on a PersonalMentalModel, a MentalModelSubscription, a MemoryPolicy, a source or a recipient; the tools check the caller's own native `use`/`subscribe_mm`/`delete` on those exact objects, so those grants stay separate, native and narrow. The roles have no wildcard, no delete or version-history verbs, no bucket CRUD and no Workspace entry grant (`access /`).
Sync waves: role `-2`, binding `-1`, bucket `0`.

Test (needs `jsonnet` on `PATH`): `python3 -m unittest discover -s tests`.
