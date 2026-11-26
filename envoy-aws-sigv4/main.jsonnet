// A ProtocolAdapter running standard Envoy that signs requests with AWS SigV4 for one fixed AWS service endpoint.
// credentials_secret is the output Secret of a CloudAuth AWS output (AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, AWS_SESSION_TOKEN).
local egregon = import '../libs/egregon.libsonnet';
local envoy = import '../libs/envoy.libsonnet';

local maxRequestBytes = 16 * 1024 * 1024;
// Headers a caller could use to present its own credentials or signature; removed before the signer sees the request.
local callerAuthHeaders = ['authorization', 'x-amz-date', 'x-amz-security-token', 'x-amz-content-sha256'];

function(name, namespace, credentials_secret, service, region, upstream_host, upstream_port='443', unsigned_payload='false', replicas='2')
  local upstreamPort = std.parseInt(upstream_port);
  local unsigned = unsigned_payload == 'true';
  local filters = [
    {
      name: 'envoy.filters.http.header_mutation',
      typed_config: envoy.typed('envoy.extensions.filters.http.header_mutation.v3.HeaderMutation', {
        mutations: { request_mutations: [{ remove: header } for header in callerAuthHeaders] },
      }),
    },
  ] + (if unsigned then [] else [{
    name: 'envoy.filters.http.buffer',
    typed_config: envoy.typed('envoy.extensions.filters.http.buffer.v3.Buffer', { max_request_bytes: maxRequestBytes }),
  }]) + [{
    name: 'envoy.filters.http.aws_request_signing',
    typed_config: envoy.typed('envoy.extensions.filters.http.aws_request_signing.v3.AwsRequestSigning', {
      service_name: service,
      region: region,
      signing_algorithm: 'AWS_SIGV4',
      host_rewrite: upstream_host,
      use_unsigned_payload: unsigned,
      credential_provider: { custom_credential_provider_chain: true, environment_credential_provider: {} },
    }),
  }, {
    // The signer lets a request through unsigned when it finds no credentials. The caller's Authorization was removed above,
    // so only a request that the signer signed carries one now; everything else is refused (403) instead of reaching AWS.
    name: 'envoy.filters.http.rbac',
    typed_config: envoy.typed('envoy.extensions.filters.http.rbac.v3.RBAC', {
      rules: { action: 'ALLOW', policies: { signed: {
        permissions: [{ any: true }],
        principals: [{ header: { name: 'authorization', present_match: true } }],
      } } },
    }),
  }];
  local config = envoy.config(upstream_host, upstreamPort, filters, [], false);
  [egregon.protocolAdapter(name, namespace, envoy.adapterSpec(config, upstream_host, upstreamPort, std.parseInt(replicas), [], [{ secretRef: { name: credentials_secret } }]))]
