local view = import 'egregon.ai/view/v1.libsonnet';
local dump = import 'dump.libsonnet';
{
  inputs(params):: { cms: view.input('', 'configmaps', { labelSelector: 'viewrt-probe in (a,b)' }) },
  render(ctx):: dump('route-ab', ctx),
}
