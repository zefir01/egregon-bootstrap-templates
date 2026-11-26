# admin-minimal

Source of the `admin-bootstrap` ClusterTemplate. The Egregon Tenant-controller only declares that ClusterTemplate; a
human launches it from the onboarding wizard with a ClusterTemplateRun, and the Template-controller renders
`main.jsonnet` and is the only writer of the outputs.

External variables (set by the ClusterTemplate source): `workspace` (the Workspace path of the Run) and `sandbox_image`
(the Sandbox executor image of the installation). Top-level string arguments: `route_kind` (`Route` or `ClusterRoute`),
`route_namespace` (`Route` only), `route_name`, `model`, and the hidden `instance_id` (a UUID chosen once by the launcher).
Optional string arguments choose the Sandbox work disk: `sandbox_storage` (absent or empty: persistent 1Gi; `none`: ephemeral
work directory in the executor container's writable layer, without PVC or volume; otherwise the size, e.g. `5Gi`) and `sandbox_storage_class_name` (absent: cluster default
class; any string, including empty, becomes `volume_claim.storageClassName` natively; invalid with `none`). Ephemeral files in
`/work` (including `.home` and `.egregon`) are lost whenever the container is re-created: a container restart in the same Pod,
suspend and Pod replacement; there is no migration between modes and the ephemeral `/work` has no size bound.

| Kind | Name | Content |
| --- | --- | --- |
| `Sandbox` | `adm-<instance_id>` | installed executor image, `default` namespace |
| `Agent` | `adm-<instance_id>` | selected Route and model, default Bucket `files`, minimal placeholder instructions, shown in the UI |
| `AgentsGroup` | `adm-<instance_id>` | one member: the Agent (`default` namespace) |
| `ClusterRoleBinding` | `adm-<instance_id>` | the native `Group` of that AgentsGroup (`egregon:agentsgroup:<workspace>/default/adm-<instance_id>`) → ClusterRole `egregon-workspace-admin`, which `tenant-defaults` owns |

Every name derives from `instance_id` alone, so a separate launch never adopts an existing output. The grant is limited to this
Workspace; no rule is defined here.
