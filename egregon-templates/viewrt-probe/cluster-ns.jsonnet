local view = import 'egregon.ai/view/v1.libsonnet';
local dump = import 'dump.libsonnet';
{
  inputs(params):: { ns: view.input('', 'namespaces', {}) },
  render(ctx):: dump('cluster-ns', ctx),
}
