local view = import 'egregon.ai/view/v1.libsonnet';
local dump = import 'dump.libsonnet';
{
  inputs(params):: { cms: view.input('', 'configmaps', { labelSelector: 'viewrt-probe=b' }) },
  render(ctx):: dump('route-b', ctx),
}
