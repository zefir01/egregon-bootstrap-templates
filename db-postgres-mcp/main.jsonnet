// An McpController and an Mcp for ONE PostgreSQL database, served by the native Toolbox SQL image of the hosted MCP
// controller (zefir01/ai-platform services/egregon/db-sql-mcp; usage and limits: docs/egregon/db-sql-mcp.md there).
//
//   image:               full image reference of egregon-db-sql-mcp (a tag or digest, as in infra/argo/revisions.yaml of ai-platform).
//   credentials_secret:  Secret of the Mcp's default login. auth_mode=password: keys `username`, `password`;
//                        auth_mode=azure-access-token: key `access_token` (a CloudAuth AzureAuth accessToken output with
//                        scope https://ossrdbms-aad.database.windows.net/.default) and access_token_user is the Entra
//                        principal the token is the password of.
//   ca_configmap:        optional ConfigMap with the public CA (key `ca.crt`) the server certificate is verified against;
//                        without it the system roots of the image are used. The server certificate is always verified
//                        (verify-full) against `host`.
//   Egress is restricted to exactly host:port; the platform links come from the hosting operator.
local egregon = import '../libs/egregon.libsonnet';

local caDir = '/etc/sql-mcp/ca';
local isIPv4(host) = std.all([c == '.' || (c >= '0' && c <= '9') for c in std.stringChars(host)]);

function(name, namespace, image, host, port, database, credentials_secret, ca_configmap='', connect_timeout='15s', replicas='2', auth_mode='password', access_token_user='')
  local profileName = name + '-profile';
  local profile = {
    SQL_MCP_ENGINE: 'postgres',
    SQL_MCP_HOST: host,
    SQL_MCP_PORT: port,
    SQL_MCP_DATABASE: database,
    SQL_MCP_AUTH_MODE: auth_mode,
    SQL_MCP_CONNECT_TIMEOUT: connect_timeout,
  } + (if access_token_user != '' then { SQL_MCP_ACCESS_TOKEN_USER: access_token_user } else {})
  + (if ca_configmap != '' then { SQL_MCP_TLS_CA_FILE: caDir + '/ca.crt' } else {});
  egregon.mcpControllerRights(name, namespace, [credentials_secret]) + [
    {
      apiVersion: 'v1',
      kind: 'ConfigMap',
      metadata: { name: profileName, namespace: namespace, annotations: { 'egregon.ai/sync-wave': '0' } },
      data: profile,
    },
    egregon.mcpController(name, namespace, {
      workload_kind: 'Deployment',
      replicas: std.parseInt(replicas),
      image: image,
      env_from: [{ configMapRef: { name: profileName } }],
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
