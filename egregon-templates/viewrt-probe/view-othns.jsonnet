local view = import 'egregon.ai/view/v1.libsonnet';
local dump = import 'dump.libsonnet';
{
  inputs(params):: { cms: view.input('', 'configmaps', { namespaces: ['viewrt-ns2'] }) },
  render(ctx):: dump('view-othns', ctx),
}
