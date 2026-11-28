local view = import 'egregon.ai/view/v1.libsonnet';
local dump = import 'dump.libsonnet';
{
  inputs(params):: { cms: view.input('', 'configmaps', { labelSelector: 'viewrt-probe=a', names: ['probe-a-1'] }) },
  render(ctx):: dump('route-names', ctx),
}
