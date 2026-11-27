// A ProtocolAdapter running standard Envoy that replaces the caller's credential header with a CloudAuth credential
// for one fixed HTTPS upstream. credentials_secret is the output Secret of a CloudAuth OAuth output; its `credential_key` key
// (default `authorization`) holds the complete header value ("Bearer <token>" for Authorization), put as is into `credential_header`
// (default Authorization); nothing is ever prefixed.
//
// Optional settings, all absent by default:
//   ca_secret / ca_key  Secret key with the PEM CA that alone validates the upstream (default key ca.crt) instead of the system
//                       trust store. The CA is mounted at start and its public key is also read as environment, so a CA change rolls the Pods.
//   route_timeout       per-request timeout, default 120s; 0s disables it.
//   stream_idle_timeout explicit idle timeout of a stream, e.g. 300s.
//   websocket_upgrade   'true' allows WebSocket upgrades.
//   external_egress     'none' leaves the adapter without any external egress rule (the upstream is cluster-internal and its
//                       access is granted by the platform administrator); the default restricts egress to the upstream host and port.
local egregon = import '../libs/egregon.libsonnet';
local envoy = import '../libs/envoy.libsonnet';

local credentialVariable = 'CLOUD_AUTHORIZATION';
local upstreamCaVariable = 'UPSTREAM_CA';
local upstreamCaDir = '/etc/envoy/upstream-ca';
local upstreamCaFile = 'ca.crt';

function(
  name,
  namespace,
  credentials_secret,
  upstream_host,
  upstream_port='443',
  replicas='2',
  credential_key='authorization',
  credential_header='Authorization',
  ca_secret='',
  ca_key='ca.crt',
  route_timeout='120s',
  stream_idle_timeout='',
  websocket_upgrade='false',
  external_egress='upstream',
)
  local upstreamPort = std.parseInt(upstream_port);
  local customCa = ca_secret != '';
  local filters = [{
    name: 'envoy.filters.http.credential_injector',
    typed_config: envoy.typed('envoy.extensions.filters.http.credential_injector.v3.CredentialInjector', {
      overwrite: true,
      allow_request_without_credential: false,
      credential: {
        name: 'envoy.http.injected_credentials.generic',
        typed_config: envoy.typed('envoy.extensions.http.injected_credentials.generic.v3.Generic', {
          credential: { name: 'cloud_authorization' },
          header: credential_header,
        }),
      },
    }),
  }];
  local secrets = [{ name: 'cloud_authorization', generic_secret: { secret: { environment_variable: credentialVariable } } }];
  local options = {
    route_timeout: route_timeout,
    websocket_upgrade: websocket_upgrade == 'true',
    [if stream_idle_timeout != '' then 'stream_idle_timeout']: stream_idle_timeout,
    [if customCa then 'ca_file']: upstreamCaDir + '/' + upstreamCaFile,
  };
  local config = envoy.config(upstream_host, upstreamPort, filters, secrets, true, options);
  local env = [{ name: credentialVariable, valueFrom: { secretKeyRef: { name: credentials_secret, key: credential_key } } }] + (if customCa then [
    { name: upstreamCaVariable, valueFrom: { secretKeyRef: { name: ca_secret, key: ca_key } } },
  ] else []);
  local volumes = if customCa then [{ name: 'upstream-ca', secret: { secretName: ca_secret, items: [{ key: ca_key, path: upstreamCaFile }] } }] else [];
  local mounts = if customCa then [{ name: 'upstream-ca', mountPath: upstreamCaDir, readOnly: true }] else [];
  [egregon.protocolAdapter(name, namespace, envoy.adapterSpec(config, upstream_host, upstreamPort, std.parseInt(replicas), env, [], volumes, mounts, external_egress == 'none'))]
