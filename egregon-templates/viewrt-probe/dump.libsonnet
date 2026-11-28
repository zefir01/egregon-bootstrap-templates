// Probe helper: one node per input object whose prose row carries the complete JSON of the object as the view received it.
local view = import 'egregon.ai/view/v1.libsonnet';
function(title, ctx)
  local names = std.objectFields(ctx.inputs);
  local objNode(n, o) =
    local id = 'o/' + n + '/' + std.get(o.metadata, 'namespace', '-') + '/' + o.metadata.name;
    view.node(id, o.metadata.name, {
      kind: o.kind,
      card: view.card([view.prose('json', std.manifestJsonMinified(o), { label: 'Object' })], [['json']]),
    });
  local groupNode(n) = view.node('in/' + n, n + ' (' + std.length(ctx.inputs[n]) + ')', {
    kind: 'Input',
    children: ['o/' + n + '/' + std.get(o.metadata, 'namespace', '-') + '/' + o.metadata.name for o in ctx.inputs[n]],
  });
  view.scene(
    ['probe'],
    view.merge(
      [view.node('probe', title, { kind: 'Probe', children: ['in/' + n for n in names] })]
      + [groupNode(n) for n in names]
      + [objNode(n, o) for n in names for o in ctx.inputs[n]]
    ),
    [],
    { title: title }
  )
