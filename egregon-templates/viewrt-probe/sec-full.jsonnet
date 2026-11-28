local view = import 'egregon.ai/view/v1.libsonnet';
local dump = import 'dump.libsonnet';
{
  inputs(params):: { secrets: view.input('', 'secrets', { labelSelector: 'viewrt-probe=sentinel', representation: 'full' }) },
  render(ctx):: dump('sec-full', ctx),
}
