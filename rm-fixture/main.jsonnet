// Disposable fixture of task run-management (hand-applied Template/ClusterTemplate rm-source / rm-cluster-source):
// one ConfigMap `rm-out-<name>` in `namespace` whose data shows the received parameters, so that render/sync of a patched Run is observable.
function(name, namespace, model, workers, verbose='false', timeout='30')
  [{
    apiVersion: 'v1',
    kind: 'ConfigMap',
    metadata: { name: 'rm-out-' + name, namespace: namespace },
    data: { model: model, workers: workers, verbose: verbose, timeout: timeout },
  }]
