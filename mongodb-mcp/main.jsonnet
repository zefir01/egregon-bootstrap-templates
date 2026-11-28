// A MongoDB MCP for one fixed MongoDB deployment: the facade controller (egregon-mongodb-mcp-facade) and, as the `upstream`
// container of the same Pod, the official MongoDB MCP server on 127.0.0.1:3000. The login is the `username` and `password`
// keys of default_secret (an ordinary Secret, or the output of a Cloud Auth producer in that layout); the deployment, its
// authentication database and its trust are fixed here, never taken from a caller.
//   hosts             comma separated approved seed hosts host:port, lower-case DNS names or IPv4 addresses; list every
//                     member of a replica set: egress is restricted to exactly these peers and ports
//   facade_image      the CI image egregon-mongodb-mcp-facade
//   server_image      the CI image egregon-mongodb-mcp-server (the official MongoDB MCP server v3.4.0, numeric user)
//   ca_configmap      optional ConfigMap of this namespace with the PEM trust anchor of the servers under the key ca.pem;
//                     without it the system roots are used. TLS with server and host name verification is always on.
//   override_secrets  optional comma separated Secrets callers may select instead of default_secret (an explicit opt-in)
local egregon = import '../libs/egregon.libsonnet';

local upstreamPort = 3000;
local caDirectory = '/etc/mongodb-ca';

// The server listens on the loopback interface only, so the kubelet (which probes the Pod address) cannot use httpGet.
// Any HTTP answer below 500 to a session-less GET proves that the HTTP server is up.
local upstreamProbe(periodSeconds, failureThreshold) = {
  exec: { command: ['node', '-e', "require('http').request({host:'127.0.0.1',port:" + upstreamPort + ",path:'/mcp',timeout:3000},res=>{res.resume();process.exit(res.statusCode<500?0:1)}).on('error',()=>process.exit(1)).on('timeout',function(){this.destroy();process.exit(1)}).end()"] },
  periodSeconds: periodSeconds,
  timeoutSeconds: 5,
  failureThreshold: failureThreshold,
};

// One external destination per seed host: exactly its address and port.
local egress(entry) =
  local parts = std.split(entry, ':');
  local ports = [{ port: std.parseInt(parts[1]), protocol: 'TCP' }];
  // A host of digits and dots only is an IPv4 address: the last label of a DNS name is never numeric.
  if std.all([c == '.' || (c >= '0' && c <= '9') for c in std.stringChars(parts[0])]) then { cidr: parts[0] + '/32', ports: ports } else { fqdn: parts[0], ports: ports };

function(name, namespace, default_secret, hosts, facade_image, server_image, auth_source='admin', replica_set='', ca_configmap='', server_selection_timeout='10s', override_secrets='', replicas='2')
  local overrides = if override_secrets == '' then [] else std.split(override_secrets, ',');
  local hasCA = ca_configmap != '';
  local env(variables) = [{ name: variable, value: variables[variable] } for variable in std.objectFields(variables)];
  local controller = egregon.mcpController(name, namespace, {
    workload_kind: 'Deployment',
    replicas: std.parseInt(replicas),
    image: facade_image,
    ports: [{ name: 'health', containerPort: 8080 }],
    startup_probe: { httpGet: { path: '/startupz', port: 'health' }, periodSeconds: 2, failureThreshold: 30 },
    readiness_probe: { httpGet: { path: '/readyz', port: 'health' }, periodSeconds: 5 },
    liveness_probe: { httpGet: { path: '/livez', port: 'health' }, periodSeconds: 10 },
    resources: { requests: { cpu: '20m', memory: '32Mi' }, limits: { cpu: '250m', memory: '128Mi' } },
    env: env({
      MONGODB_MCP_UPSTREAM_URL: 'http://127.0.0.1:' + upstreamPort + '/mcp',
      MONGODB_SEED_HOSTS: hosts,
      MONGODB_AUTH_SOURCE: auth_source,
      MONGODB_SERVER_SELECTION_TIMEOUT: server_selection_timeout,
      OTEL_EXPORTER_OTLP_ENDPOINT: 'http://telemetry-router.observability.svc.cluster.local:4317',
    } + (if replica_set == '' then {} else { MONGODB_REPLICA_SET: replica_set })
      + (if hasCA then { MONGODB_TLS_CA_FILE: caDirectory + '/ca.pem' } else {})),
    network_policy: { external: { mode: 'Restricted', rules: [egress(entry) for entry in std.split(hosts, ',')] } },
    [if hasCA then 'volumes']: [{ name: 'mongodb-ca', configMap: { name: ca_configmap, items: [{ key: 'ca.pem', path: 'ca.pem' }] } }],
    upstream: {
      image: server_image,
      // connectionScope=session: a connection belongs to one MCP session; no connection string is preconfigured; no
      // telemetry; no logger (the default loggers would write the hidden connect); the connection reaper is off so that a
      // connection lives as long as its session, whose idle timeout (15m) is longer than the facade's idle session (10m).
      env: env({
        MDB_MCP_TRANSPORT: 'http',
        MDB_MCP_HTTP_HOST: '127.0.0.1',
        MDB_MCP_HTTP_PORT: std.toString(upstreamPort),
        MDB_MCP_CONNECTION_SCOPE: 'session',
        MDB_MCP_TELEMETRY: 'disabled',
        MDB_MCP_LOGGERS: '',
        MDB_MCP_READ_ONLY: 'false',
        MDB_MCP_CONNECTION_IDLE_TIMEOUT_MS: '0',
        MDB_MCP_IDLE_TIMEOUT_MS: '900000',
        MDB_MCP_NOTIFICATION_TIMEOUT_MS: '840000',
      }),
      resources: { requests: { cpu: '50m', memory: '192Mi' }, limits: { cpu: '500m', memory: '768Mi' } },
      startup_probe: upstreamProbe(2, 60),
      readiness_probe: upstreamProbe(10, 3),
      liveness_probe: upstreamProbe(20, 3),
      [if hasCA then 'volume_mounts']: [{ name: 'mongodb-ca', mountPath: caDirectory, readOnly: true }],
    },
  });
  egregon.mcpControllerRights(name, namespace, [default_secret] + overrides) + [
    controller,
    egregon.mcp(name, namespace, {
      controller_ref: { namespace: namespace, name: name },
      default_secret_name: default_secret,
      allow_secret_override: std.length(overrides) > 0,
      tools_whitelist: ['*'],
    }),
  ]
