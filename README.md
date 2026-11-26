# egregon-bootstrap-templates

Public, credential-free sources of the templates that the Egregon Tenant-controller bootstraps into every new Tenant.
Only bootstrap templates and their non-secret dependencies belong here.
Resource constructors live in [`libs/`](libs/README.md); templates declare their settings and permissions.

* [`tenant-defaults/`](tenant-defaults/README.md): the base resources of a Tenant (shared bucket `files` and its narrow data grant).
* [`admin-minimal/`](admin-minimal/README.md): the minimal administrator Agent, its Sandbox and a one-member AgentsGroup bound to the Workspace-admin role, launched by a human. Its Sandbox work disk is persistent by default; the helper `sandbox(..., storage='1Gi', storage_class_name=null)` and the admin-minimal arguments `sandbox_storage`/`sandbox_storage_class_name` select a size, a StorageClass or an ephemeral work directory in the container's writable layer (`storage=null` / `none`; lost on every container re-creation, including a container restart in the same Pod, suspend and Pod replacement; no volume, no size bound, no migration).
* [`envoy-aws-sigv4/`](envoy-aws-sigv4/main.jsonnet), [`envoy-bearer/`](envoy-bearer/main.jsonnet), [`sshpiper-fixed-upstream/`](sshpiper-fixed-upstream/main.jsonnet): ready ProtocolAdapter consumers of Cloud Auth output Secrets (stock Envoy v1.40.2 and sshpiperd v1.6.2 images pinned by digest). They are not bootstrapped into every Tenant: `consumer-templates.jsonnet` renders their Template/ClusterTemplate declarations for an exact commit of this repository. Usage, Secret keys and limits: `docs/egregon/cloud-auth-consumers.md` in zefir01/ai-platform.

Test: `python3 -m unittest discover -s tests` (needs `jsonnet`).
