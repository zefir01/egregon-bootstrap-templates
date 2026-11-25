# egregon-bootstrap-templates

Public, credential-free sources of the templates that the Egregon Tenant-controller bootstraps into every new Tenant.
Only bootstrap templates and their non-secret dependencies belong here.
Resource constructors live in [`libs/`](libs/README.md); templates declare their settings and permissions.

* [`tenant-defaults/`](tenant-defaults/README.md): the base resources of a Tenant (shared bucket `files` and its narrow data grant).
* [`admin-minimal/`](admin-minimal/README.md): the minimal administrator Agent, its Sandbox and a one-member AgentsGroup bound to the Workspace-admin role, launched by a human. Its Sandbox work disk is persistent by default; the helper `sandbox(..., storage='1Gi', storage_class_name=null)` and the admin-minimal arguments `sandbox_storage`/`sandbox_storage_class_name` select a size, a StorageClass or an ephemeral `emptyDir` (`storage=null` / `none`; lost on suspend and Pod replacement, no migration).

Test: `python3 -m unittest discover -s tests` (needs `jsonnet`).
