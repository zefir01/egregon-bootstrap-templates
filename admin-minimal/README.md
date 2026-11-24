# admin-minimal

Source of the `admin-bootstrap` ClusterTemplate. The Egregon Tenant-controller only declares that ClusterTemplate; a
human launches it from the onboarding wizard with a ClusterTemplateRun, and the Template-controller renders
`main.jsonnet` and is the only writer of the outputs.

External variables (set by the ClusterTemplate source): `workspace` (the Workspace path of the Run) and `sandbox_image`
(the Sandbox executor image of the installation). Top-level string arguments: `route_kind` (`Route` or `ClusterRoute`),
`route_namespace` (`Route` only), `route_name`, `model`, and the hidden `instance_id` (a UUID chosen once by the launcher).

| Kind | Name | Content |
| --- | --- | --- |
| `Sandbox` | `adm-<instance_id>` | installed executor image, `default` namespace |
| `Agent` | `adm-<instance_id>` | selected Route and model, default Bucket `files`, minimal placeholder instructions, shown in the UI |
| `AgentsGroup` | `adm-<instance_id>` | one member: the Agent (`default` namespace) |
| `ClusterRoleBinding` | `adm-<instance_id>` | the native `Group` of that AgentsGroup (`egregon:agentsgroup:<workspace>/default/adm-<instance_id>`) → ClusterRole `egregon-workspace-admin`, which `tenant-defaults` owns |

Every name derives from `instance_id` alone, so a separate launch never adopts an existing output. The grant is limited to this
Workspace; no rule is defined here.
