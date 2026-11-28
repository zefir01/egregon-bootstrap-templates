local view = import 'egregon.ai/view/v1.libsonnet';
local dump = import 'dump.libsonnet';
{
  inputs(params):: { t: view.input('authentication.k8s.io', 'tokenreviews', {}) },
  render(ctx):: dump('unsupported', ctx),
}
