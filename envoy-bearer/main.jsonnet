// A ProtocolAdapter running standard Envoy that replaces the caller's Authorization header with a CloudAuth OAuth credential
// for one fixed HTTPS upstream. credentials_secret is the output Secret of a CloudAuth OAuth output; its `authorization` key
// holds the complete header value ("Bearer <token>").
local egregon = import '../libs/egregon.libsonnet';
local envoy = import '../libs/envoy.libsonnet';

local credentialVariable = 'CLOUD_AUTHORIZATION';

function(name, namespace, credentials_secret, upstream_host, upstream_port='443', replicas='2')
  local upstreamPort = std.parseInt(upstream_port);
  local filters = [{
    name: 'envoy.filters.http.credential_injector',
    typed_config: envoy.typed('envoy.extensions.filters.http.credential_injector.v3.CredentialInjector', {
      overwrite: true,
      allow_request_without_credential: false,
      credential: {
        name: 'envoy.http.injected_credentials.generic',
        typed_config: envoy.typed('envoy.extensions.http.injected_credentials.generic.v3.Generic', {
          credential: { name: 'cloud_authorization' },
          header: 'Authorization',
        }),
      },
    }),
  }];
  local secrets = [{ name: 'cloud_authorization', generic_secret: { secret: { environment_variable: credentialVariable } } }];
  local config = envoy.config(upstream_host, upstreamPort, filters, secrets, true);
  local env = [{ name: credentialVariable, valueFrom: { secretKeyRef: { name: credentials_secret, key: 'authorization' } } }];
  [egregon.protocolAdapter(name, namespace, envoy.adapterSpec(config, upstream_host, upstreamPort, std.parseInt(replicas), env, []))]
