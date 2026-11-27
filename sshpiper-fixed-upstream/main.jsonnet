// A ProtocolAdapter running stock sshpiperd with its Lua plugin: every SSH client that may use the adapter is piped, without
// authenticating to the adapter, to one fixed upstream host, port and user. The frontend username has no authority.
//
//   frontend_key_secret: Secret with `host_key` (private key, loaded once at start) and `host_key.pub` (its public key).
//   upstream_secret:     Secret with `known_hosts` (the pinned upstream host key) and, per `credential`, `password` or `private_key`.
//                        Mounted read-only; the script reads the files on every new connection, so an update applies without restart.
//   credential_key:      optional Secret key under which the credential is stored when it is not named like `credential` (for example
//                        ssh-private-key for `private_key`); only that key is mounted, as the file the script reads.
//   known_hosts_configmap: optional public ConfigMap whose `known_hosts` key replaces the known_hosts of upstream_secret; then
//                        only the credential is read from upstream_secret. Also read on every new connection.
local egregon = import '../libs/egregon.libsonnet';

// ghcr.io/tg123/sshpiperd:full-v1.6.2 (source 30a0125430d38f0fffd9bc824e05fc6206c340a7), pinned by the digest of the index.
local image = 'ghcr.io/tg123/sshpiperd:full-v1.6.2@sha256:fde25327a531c08885629aec8db5534ffed68018054e6d58544308a244c6d7fa';
local listenPort = 2222;
local frontendDir = '/etc/sshpiper/frontend';
local upstreamDir = '/etc/sshpiper/upstream';
local scriptDir = '/etc/sshpiper/script';
// The only key of the script ConfigMap. It is a valid variable name so that the ConfigMap can also be consumed as environment:
// the adapter then rolls its Pods whenever the script changes (mounted files alone never restart it).
local scriptKey = 'SSHPIPER_SCRIPT';
local knownHostsConfigMapDir = '/etc/sshpiper/upstream-known-hosts';
// The same directory as the script reads it, relative to upstreamDir.
local knownHostsConfigMapFile = '../upstream-known-hosts/known_hosts';

local isIPv4(host) = std.all([c == '.' || (c >= '0' && c <= '9') for c in std.stringChars(host)]);

// `credential` is the Secret key of the upstream credential, `password` or `private_key`; the plugin names the second field private_key_data.
// known_hosts_file is relative to the upstream directory.
local script(upstream_host, upstream_port, upstream_user, credential, known_hosts_file) =
  |||
  local function read(name)
    local file = io.open("%(dir)s/" .. name, "rb")
    if file == nil then
      return nil
    end
    local content = file:read("*a")
    file:close()
    if content == "" then
      return nil
    end
    return content
  end

  function sshpiper_on_noauth(conn)
    local known_hosts = read("%(known_hosts_file)s")
    local credential = read("%(credential)s")
    if known_hosts == nil or credential == nil then
      sshpiper_log("error", "upstream known_hosts or %(credential)s is missing or empty; refusing the connection")
      return nil
    end
    return {
      host = "%(host)s:%(port)d",
      username = "%(user)s",
      known_hosts_data = known_hosts,
      %(field)s = credential,
    }
  end
||| % { dir: upstreamDir, known_hosts_file: known_hosts_file, credential: credential, host: upstream_host, port: upstream_port, user: upstream_user, field: if credential == 'password' then 'password' else 'private_key_data' };

function(name, namespace, frontend_key_secret, upstream_secret, upstream_host, upstream_user, upstream_port='22', credential='password', replicas='2', credential_key='', known_hosts_configmap='')
  local port = std.parseInt(upstream_port);
  local ownKnownHosts = known_hosts_configmap == '';
  local items = (if credential_key != '' then [{ key: credential_key, path: credential }] else []) +
                (if credential_key != '' && ownKnownHosts then [{ key: 'known_hosts', path: 'known_hosts' }] else []);
  local upstreamSecretVolume = { name: 'upstream', secret: { secretName: upstream_secret } + (if std.length(items) > 0 then { items: items } else {}) };
  local scriptName = name + '-script';
  [
    {
      apiVersion: 'v1',
      kind: 'ConfigMap',
      metadata: { name: scriptName, namespace: namespace, annotations: { 'egregon.ai/sync-wave': '0' } },
      data: { [scriptKey]: script(upstream_host, port, upstream_user, credential, if ownKnownHosts then 'known_hosts' else knownHostsConfigMapFile) },
    },
    egregon.protocolAdapter(name, namespace, {
      image: image,
      replicas: std.parseInt(replicas),
      ports: [{ name: 'ssh', port: 22, target_port: listenPort }],
      args: [
        '--port=' + listenPort,
        '--server-key=' + frontendDir + '/host_key',
        '--server-key-generate-mode=disable',
        '/sshpiperd/plugins/lua',
        '--script=' + scriptDir + '/' + scriptKey,
      ],
      // Only the public key is read as environment: replacing the frontend key replaces it, which rolls the Pods.
      env: [{ name: 'FRONTEND_HOST_PUBLIC_KEY', valueFrom: { secretKeyRef: { name: frontend_key_secret, key: 'host_key.pub' } } }],
      env_from: [{ configMapRef: { name: scriptName } }],
      volumes: [
        { name: 'frontend-key', secret: { secretName: frontend_key_secret, items: [{ key: 'host_key', path: 'host_key' }] } },
        upstreamSecretVolume,
        { name: 'script', configMap: { name: scriptName } },
      ] + (if ownKnownHosts then [] else [{ name: 'upstream-known-hosts', configMap: { name: known_hosts_configmap, items: [{ key: 'known_hosts', path: 'known_hosts' }] } }]),
      volume_mounts: [
        { name: 'frontend-key', mountPath: frontendDir, readOnly: true },
        { name: 'upstream', mountPath: upstreamDir, readOnly: true },
        { name: 'script', mountPath: scriptDir, readOnly: true },
      ] + (if ownKnownHosts then [] else [{ name: 'upstream-known-hosts', mountPath: knownHostsConfigMapDir, readOnly: true }]),
      resources: { requests: { cpu: '50m', memory: '64Mi' }, limits: { cpu: '500m', memory: '256Mi' } },
      readiness_probe: { tcpSocket: { port: listenPort } },
      network_policy: { external: { mode: 'Restricted', rules: [
        { [if isIPv4(upstream_host) then 'cidr' else 'fqdn']: if isIPv4(upstream_host) then upstream_host + '/32' else upstream_host, ports: [{ port: port, protocol: 'TCP' }] },
      ] } },
    }),
  ]
