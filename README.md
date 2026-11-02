# egregon-bootstrap-templates

Public, credential-free sources of the templates that the Egregon Tenant-controller bootstraps into every new Tenant.
Only bootstrap templates and their non-secret dependencies belong here.

* [`tenant-defaults/`](tenant-defaults/README.md): the base resources of a Tenant (shared bucket `files` and its narrow data grant).

Test: `python3 -m unittest discover -s tests` (needs `jsonnet`).
