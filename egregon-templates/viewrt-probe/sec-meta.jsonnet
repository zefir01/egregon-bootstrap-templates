local view = import 'egregon.ai/view/v1.libsonnet';
local dump = import 'dump.libsonnet';
{
  inputs(params):: { secrets: view.input('', 'secrets', { labelSelector: 'viewrt-probe=sentinel' }) },
  render(ctx):: dump('sec-meta', ctx),
}
