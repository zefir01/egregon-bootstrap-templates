local view = import 'egregon.ai/view/v1.libsonnet';
local dump = import 'dump.libsonnet';
{
  inputs(params):: { w: view.input('probe.viewrt.test', 'widgets', {}) },
  render(ctx):: dump('late', ctx),
}
