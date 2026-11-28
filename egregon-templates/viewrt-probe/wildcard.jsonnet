local view = import 'egregon.ai/view/v1.libsonnet';
local dump = import 'dump.libsonnet';
{
  inputs(params):: { all: view.input('*', '*', { labelSelector: 'viewrt-probe=wild' }) },
  render(ctx):: dump('wildcard', ctx),
}
