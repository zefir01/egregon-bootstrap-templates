// Only this file is rendered by the ClusterTemplate; the view program itself is view.jsonnet, executed by the
// ViewController from the exact installed revision of this source.
function(recent_window_minutes='15')
  {
    apiVersion: 'egregon.ai/v1alpha1',
    kind: 'ClusterView',
    // The graph window recognises the default view by this name.
    metadata: { name: 'default' },
    spec: {
      programPath: 'view.jsonnet',
      parameters: { recentWindowMinutes: std.parseInt(recent_window_minutes) },
      refreshInterval: '30s',
    },
  }
