// The standard Envoy v1.40.2 image (source b2d89e0ae53916f28770771fbdd49c5c99c5c5a2), distroless variant: its default user is 65532,
// which the ProtocolAdapter Pod (runAsNonRoot) requires; the binary is the same file as in the Debian variant.
// Pinned by the digest of the multi-architecture index.
local image = 'envoyproxy/envoy:distroless-v1.40.2@sha256:09ca6f2140a61ad8df11779a4a30d52b48433d444466328494f9188c9c35eded';
local typed(type, body) = { '@type': 'type.googleapis.com/' + type } + body;
local router = { name: 'envoy.filters.http.router', typed_config: typed('envoy.extensions.filters.http.router.v3.Router', {}) };
local proxyPort = 8080;
local healthPort = 8081;

{
  typed:: typed,

  // One plain-HTTP listener (the ProtocolAdapter Service is the only way to it) forwarding to the one fixed HTTPS upstream, and a
  // separate health listener that no filter sees. There is no admin interface. rewrite_host is true when the route itself sets
  // the upstream Host; the AWS signer rewrites it before signing instead.
  config(upstream_host, upstream_port, http_filters, secrets, rewrite_host):: {
    static_resources: {
      [if std.length(secrets) > 0 then 'secrets']: secrets,
      listeners: [
        {
          name: 'proxy',
          address: { socket_address: { address: '0.0.0.0', port_value: proxyPort } },
          filter_chains: [{ filters: [{
            name: 'envoy.filters.network.http_connection_manager',
            typed_config: typed('envoy.extensions.filters.network.http_connection_manager.v3.HttpConnectionManager', {
              stat_prefix: 'proxy',
              route_config: { virtual_hosts: [{
                name: 'upstream',
                domains: ['*'],
                routes: [{
                  match: { prefix: '/' },
                  route: { cluster: 'upstream', timeout: '120s' } + (if rewrite_host then { host_rewrite_literal: upstream_host } else {}),
                }],
              }] },
              http_filters: http_filters + [router],
            }),
          }] }],
        },
        {
          name: 'health',
          address: { socket_address: { address: '0.0.0.0', port_value: healthPort } },
          filter_chains: [{ filters: [{
            name: 'envoy.filters.network.http_connection_manager',
            typed_config: typed('envoy.extensions.filters.network.http_connection_manager.v3.HttpConnectionManager', {
              stat_prefix: 'health',
              route_config: { virtual_hosts: [{
                name: 'health',
                domains: ['*'],
                routes: [{ match: { prefix: '/' }, direct_response: { status: 200, body: { inline_string: 'ok' } } }],
              }] },
              http_filters: [router],
            }),
          }] }],
        },
      ],
      clusters: [{
        name: 'upstream',
        type: 'STRICT_DNS',
        dns_lookup_family: 'V4_ONLY',
        connect_timeout: '10s',
        load_assignment: {
          cluster_name: 'upstream',
          endpoints: [{ lb_endpoints: [{ endpoint: { address: { socket_address: { address: upstream_host, port_value: upstream_port } } } }] }],
        },
        transport_socket: {
          name: 'envoy.transport_sockets.tls',
          typed_config: typed('envoy.extensions.transport_sockets.tls.v3.UpstreamTlsContext', {
            sni: upstream_host,
            common_tls_context: { validation_context: {
              trusted_ca: { filename: '/etc/ssl/certs/ca-certificates.crt' },
              match_typed_subject_alt_names: [{ san_type: 'DNS', matcher: { exact: upstream_host } }],
            } },
          }),
        },
      }],
    },
  },

  // The ProtocolAdapter spec: Envoy takes its whole configuration from --config-yaml, so a configuration change changes the
  // Deployment and rolls it; credentials arrive as environment and roll the Pods through the adapter's environment digest.
  // Egress is restricted to the one upstream host and port.
  adapterSpec(config, upstream_host, upstream_port, replicas, env, env_from):: {
    image: image,
    replicas: replicas,
    ports: [{ name: 'http', port: 80, target_port: proxyPort }],
    args: ['--config-yaml', std.manifestJsonMinified(config), '--disable-hot-restart', '--log-level', 'info'],
    env: env,
    env_from: env_from,
    resources: { requests: { cpu: '50m', memory: '64Mi' }, limits: { cpu: '500m', memory: '256Mi' } },
    readiness_probe: { httpGet: { path: '/', port: healthPort } },
    network_policy: { external: { mode: 'Restricted', rules: [{ fqdn: upstream_host, ports: [{ port: upstream_port, protocol: 'TCP' }] }] } },
  },
}
