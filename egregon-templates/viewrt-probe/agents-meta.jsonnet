local view = import 'egregon.ai/view/v1.libsonnet';
local dump = import 'dump.libsonnet';
{
  inputs(params):: { agents: view.input('egregon.ai', 'agents', {}) },
  render(ctx):: dump('agents-meta', ctx),
}
