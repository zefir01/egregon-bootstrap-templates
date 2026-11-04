# Bootstrap libraries

A self-contained subset of the libraries in `zefir01/ai-platform` at `8ac7bc581`:

- `k8s.libsonnet`: `cluster_role`, `role`, `roleBinding`, `clusterRoleBinding` from
  `infra/argo/libs/k8s.libsonnet`, expressed as methods with `::`.
- `egregon.libsonnet`: scoped `permission` and paired role/binding `grant` from
  `egregon-templates/libs/egregon.libsonnet`, plus the bootstrap `clusterBucket` template.

No Argo config, external variables or files outside this repository are needed.
Only constructors required by the bootstrap resources are included.

`grant` returns a role and its binding. `namespace=null` selects cluster scope;
`principal_kind='Group'` binds a group instead of a user. The resource names and
verbs remain explicit in the template. `wave` and `binding_wave` use Egregon
annotations; the Kubernetes constructors' Argo wave option is not passed.

`clusterBucket` takes the presigned URL TTL, versioning status and object-lock
setting explicitly. It adds no lifecycle or expiration policy.
