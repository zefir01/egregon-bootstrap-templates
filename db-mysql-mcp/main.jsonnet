// An McpController and an Mcp for ONE MySQL database, served by the native Toolbox SQL image of the hosted MCP
// controller (zefir01/ai-platform services/egregon/db-sql-mcp; usage and limits: docs/egregon/db-sql-mcp.md there).
//
//   image:               full image reference of egregon-db-sql-mcp (a tag or digest, as in infra/argo/revisions.yaml of ai-platform).
//   credentials_secret:  Secret of the Mcp's default login: keys `username` (without ':'), `password`.
//   ca_configmap:        optional ConfigMap with the public CA (key `ca.crt`) the server certificate is verified against;
//                        without it the system roots of the image are used. The server certificate is always verified,
//                        against tls_server_name (default `host`).
//                        The CA is read when the process starts and a same-name ConfigMap edit does not roll the Pod: publish the new
//                        CA as a new ConfigMap name and change this argument.
//   The non-secret profile is McpController.spec.env: changing any argument changes the Pod template and rolls the Pods.
//   Egress is restricted to exactly host:port; the platform links come from the hosting operator.
local egregon = import '../libs/egregon.libsonnet';

local caDir = '/etc/sql-mcp/ca';
local isIPv4(host) = std.all([c == '.' || (c >= '0' && c <= '9') for c in std.stringChars(host)]);

function(name, namespace, image, host, port, database, credentials_secret, ca_configmap='', tls_server_name='', connect_timeout='15s', replicas='2')
  local profile = {
    SQL_MCP_ENGINE: 'mysql',
    SQL_MCP_HOST: host,
    SQL_MCP_PORT: port,
    SQL_MCP_DATABASE: database,
    SQL_MCP_AUTH_MODE: 'password',
    SQL_MCP_CONNECT_TIMEOUT: connect_timeout,
  } + (if tls_server_name != '' then { SQL_MCP_TLS_SERVER_NAME: tls_server_name } else {})
  + (if ca_configmap != '' then { SQL_MCP_TLS_CA_FILE: caDir + '/ca.crt' } else {});
  egregon.mcpControllerRights(name, namespace, [credentials_secret]) + [
    egregon.mcpController(name, namespace, {
      workload_kind: 'Deployment',
      replicas: std.parseInt(replicas),
      image: image,
      env: [{ name: key, value: profile[key] } for key in std.objectFields(profile)],
      resources: { requests: { cpu: '50m', memory: '96Mi' }, limits: { cpu: '500m', memory: '512Mi' } },
      network_policy: { external: { mode: 'Restricted', rules: [
        { [if isIPv4(host) then 'cidr' else 'fqdn']: if isIPv4(host) then host + '/32' else host, ports: [{ port: std.parseInt(port), protocol: 'TCP' }] },
      ] } },
    } + (if ca_configmap != '' then {
      volumes: [{ name: 'ca', configMap: { name: ca_configmap, items: [{ key: 'ca.crt', path: 'ca.crt' }] } }],
      volume_mounts: [{ name: 'ca', mountPath: caDir, readOnly: true }],
    } else {})),
    egregon.mcp(name, namespace, {
      controller_ref: { namespace: namespace, name: name },
      default_secret_name: credentials_secret,
      allow_secret_override: false,
      tools_whitelist: ['*'],
    }),
  ]
