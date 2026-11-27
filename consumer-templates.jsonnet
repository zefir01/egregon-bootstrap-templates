// The Template (namespace given) or ClusterTemplate (namespace=null) declarations of the ready consumer sources of this
// repository. Render and apply them to a Workspace at an exact commit of this repository:
//   jsonnet -y -J . consumer-templates.jsonnet --tla-str revision=<commit> --tla-str namespace=development | kubectl apply -f -
// (omit namespace for ClusterTemplates).
local egregon = import 'libs/egregon.libsonnet';

local label = { type: 'string', minLength: 1, maxLength: 63, pattern: '^[a-z0-9]([-a-z0-9]*[a-z0-9])?$' };
local secretName = { type: 'string', minLength: 1, maxLength: 253, pattern: '^[a-z0-9]([-a-z0-9.]*[a-z0-9])?$' };
local hostname = { type: 'string', minLength: 1, maxLength: 253, pattern: '^[a-z0-9]([-a-z0-9.]*[a-z0-9])?$' };
local port = { type: 'string', pattern: '^[1-9][0-9]{0,4}$' };
local replicas = { type: 'string', pattern: '^[0-9]{1,2}$' };
local bool = { type: 'string', enum: ['true', 'false'] };
local seedHosts = { type: 'string', minLength: 1, maxLength: 1024, pattern: '^[a-z0-9]([a-z0-9.-]*[a-z0-9])?:[1-9][0-9]{0,4}(,[a-z0-9]([a-z0-9.-]*[a-z0-9])?:[1-9][0-9]{0,4})*$' };
local imageReference = { type: 'string', minLength: 1, maxLength: 512, pattern: '^[^\\s]+$' };
local secretNames = { type: 'string', pattern: '^[a-z0-9]([-a-z0-9.]*[a-z0-9])?(,[a-z0-9]([-a-z0-9.]*[a-z0-9])?)*$' };
local sshUser = { type: 'string', minLength: 1, maxLength: 32, pattern: '^[A-Za-z_][A-Za-z0-9_.-]*$' };

function(revision, namespace=null)
  local declare(name, display, optional, arguments) =
    egregon.template(name, namespace, name, revision, egregon.parameters(arguments, optional=optional), display);
  [
    declare('envoy-aws-sigv4', 'Cloud Auth — Envoy AWS SigV4 adapter', ['upstream_port', 'unsigned_payload', 'replicas'], {
      name: label,
      namespace: label,
      credentials_secret: secretName,
      service: { type: 'string', pattern: '^[a-z0-9-]{1,64}$' },
      region: { type: 'string', pattern: '^[a-z0-9-]{1,32}$' },
      upstream_host: hostname,
      upstream_port: port,
      unsigned_payload: bool,
      replicas: replicas,
    }),
    declare('envoy-bearer', 'Cloud Auth — Envoy Bearer credential adapter', ['upstream_port', 'replicas'], {
      name: label,
      namespace: label,
      credentials_secret: secretName,
      upstream_host: hostname,
      upstream_port: port,
      replicas: replicas,
    }),
    declare('mongodb-mcp', 'Cloud DB — MongoDB MCP', ['auth_source', 'replica_set', 'ca_configmap', 'server_selection_timeout', 'override_secrets', 'replicas'], {
      name: label,
      namespace: label,
      default_secret: secretName,
      hosts: seedHosts,
      facade_image: imageReference,
      server_image: imageReference,
      auth_source: { type: 'string', pattern: '^[A-Za-z0-9_.$-]{1,64}$' },
      replica_set: { type: 'string', pattern: '^[A-Za-z0-9_.-]{1,64}$' },
      ca_configmap: secretName,
      server_selection_timeout: { type: 'string', pattern: '^[1-9][0-9]{0,4}(ms|s)$' },
      override_secrets: secretNames,
      replicas: replicas,
    }),
    declare('sshpiper-fixed-upstream', 'Cloud Auth — SSH adapter to one fixed upstream', ['upstream_port', 'credential', 'replicas'], {
      name: label,
      namespace: label,
      frontend_key_secret: secretName,
      upstream_secret: secretName,
      upstream_host: hostname,
      upstream_user: sshUser,
      upstream_port: port,
      credential: { type: 'string', enum: ['password', 'private_key'] },
      replicas: replicas,
    }),
  ]
