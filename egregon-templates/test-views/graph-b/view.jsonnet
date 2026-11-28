// Disposable QA fixture for the graph window (journey B). Reads only kcp inputs (no telemetry).
// Members are ConfigMaps and Agents labelled demo=graph; each is placed in the regions its annotation
// demo.egregon.ai/regions lists, so one real resource appears in several regions under different visual IDs.
// Display filter "tier" hides the intermediate owners ("mid") by default; ownership edges then contract across them.
local view = import 'egregon.ai/view/v1.libsonnet';

local agentFields = [
  '/metadata/annotations',
  '/metadata/labels',
  '/metadata/ownerReferences',
  '/metadata/creationTimestamp',
  '/status/activity',
];
local ann(o, key, default='') = std.get(std.get(o.metadata, 'annotations', {}), 'demo.egregon.ai/' + key, default);
local toneOf(state) = if state == 'ok' then 'success' else if state == 'warn' then 'warning' else if state == 'bad' then 'danger' else 'neutral';
local tiers = ['root', 'mid', 'leaf', 'agent'];

{
  inputs(params):: {
    configmaps: view.input('', 'configmaps', { labelSelector: 'demo=graph' }),
    agents: view.input('egregon.ai', 'agents', { labelSelector: 'demo=graph', representation: 'full', fields: agentFields }),
  },

  render(ctx)::
    local regionNames = std.get(ctx.params, 'regions', ['alpha', 'beta']);
    local members =
      [{ obj: o, kind: 'ConfigMap', resource: 'configmaps', tier: ann(o, 'tier', 'leaf') } for o in ctx.inputs.configmaps] +
      [{ obj: o, kind: 'Agent', resource: 'agents', tier: 'agent' } for o in ctx.inputs.agents];
    local sorted = std.sort(members, function(m) m.obj.metadata.name);
    local byUid = { [m.obj.metadata.uid]: m for m in sorted };
    local regionsOf(m) = [r for r in std.split(ann(m.obj, 'regions', regionNames[0]), ',') if std.member(regionNames, r)];
    local inRegion(r) = [m for m in sorted if std.member(regionsOf(m), r)];
    local vid(r, m) = r + '/' + m.obj.metadata.uid;
    local ownersOf(m) = [byUid[ref.uid] for ref in std.get(m.obj.metadata, 'ownerReferences', []) if std.objectHas(byUid, ref.uid)];
    local stateOf(m) = ann(m.obj, 'state', 'ok');
    local ownerNames(m) = std.join(', ', [o.obj.metadata.name for o in ownersOf(m)]);

    local memberNode(r, m) = view.node(vid(r, m), m.obj.metadata.name, {
      kind: m.kind,
      tone: toneOf(stateOf(m)),
      resourceRef: view.resourceRef(m.obj, m.resource),
      card: view.card(
        [
          view.line('state', stateOf(m), { label: 'State', tone: toneOf(stateOf(m)) }),
          view.line('tier', m.tier, { label: 'Tier' }),
          view.line('owners', if ownerNames(m) == '' then 'none' else ownerNames(m), { label: 'Owned by' }),
          view.packed('regions', regionsOf(m), { label: 'Regions' }),
          view.prose('note', ann(m.obj, 'note', 'No note.')),
        ],
        [['state'], ['state', 'tier', 'owners'], ['state', 'tier', 'owners', 'regions', 'note']]
      ),
      panel: if m.kind == 'Agent'
      then view.panelMarkdown(m.obj.metadata.name, '**Agent** `' + m.obj.metadata.uid + '`\n\nRegion instance: `' + r + '`. ' + ann(m.obj, 'note', ''))
      else view.panelTable(m.obj.metadata.name, [
        ['Kind', m.kind],
        ['UID', m.obj.metadata.uid],
        ['Region instance', r],
        ['Tier', m.tier],
        ['State', stateOf(m)],
        ['Owned by', ownerNames(m)],
      ]),
      facets: { tier: [m.tier], kind: [m.kind] },
    });

    local count(list, tier) = std.length([m for m in list if m.tier == tier]);
    local regionNode(r) =
      local list = inRegion(r);
      local worst = if std.length([m for m in list if stateOf(m) == 'bad']) > 0 then 'danger'
                    else if std.length([m for m in list if stateOf(m) == 'warn']) > 0 then 'warning' else 'success';
      local sharedCount = std.length([m for m in list if std.length(regionsOf(m)) > 1]);
      view.node('region/' + r, 'Region ' + r, {
        kind: 'Region',
        tone: worst,
        children: [vid(r, m) for m in list],
        card: view.card(
          [
            view.line('members', '%d members, %d warnings, %d failing' % [
              std.length(list),
              std.length([m for m in list if stateOf(m) == 'warn']),
              std.length([m for m in list if stateOf(m) == 'bad']),
            ], { label: 'Aggregate', tone: worst }),
            view.packed('tiers', ['%s %d' % [t, count(list, t)] for t in tiers if count(list, t) > 0], { label: 'Tiers' }),
            view.prose('about', 'Aggregate of region %s only; %d of its members also appear in another region under their own visual ID.' % [r, sharedCount]),
          ],
          [['members'], ['members', 'tiers'], ['members', 'tiers', 'about']]
        ),
        panel: view.panelTable('Region ' + r, [['Members', std.length(list)], ['Shared with another region', sharedCount], ['Worst state', worst]]),
        facets: { tier: tiers, kind: ['ConfigMap', 'Agent'] },
      });

    local rootNode = view.node('demo', 'Graph demo namespace', {
      kind: 'Namespace',
      tone: 'info',
      children: ['region/' + r for r in regionNames],
      card: view.card(
        [
          view.line('summary', '%d regions, %d resources' % [std.length(regionNames), std.length(sorted)], { label: 'Contents' }),
          view.packed('regions', regionNames, { label: 'Regions' }),
          view.prose('about', 'Disposable QA scene: ownership chains with hidden intermediates, one real resource in two regions, mixed edges.'),
        ],
        [['summary'], ['summary', 'regions'], ['summary', 'regions', 'about']]
      ),
      panel: view.panelMarkdown('Graph demo', 'Disposable fixture for the graph window. Display filter **Tier** hides *mid* owners by default.'),
      facets: { tier: tiers, kind: ['ConfigMap', 'Agent'] },
    });

    local ownership = [
      view.edge('own/' + r + '/' + o.obj.metadata.uid + '/' + m.obj.metadata.uid, vid(r, o), vid(r, m), 'ownership')
      for r in regionNames
      for m in inRegion(r)
      for o in ownersOf(m)
      if std.member(regionsOf(o), r)
    ];
    // Non-ownership edges: author-declared references "kind|label|target-name" in annotation demo.egregon.ai/links.
    local byName = { [m.obj.metadata.name]: m for m in sorted };
    local linkEdges = [
      local parts = std.split(link, '|');
      view.edge('link/' + r + '/' + m.obj.metadata.uid + '/' + parts[2], vid(r, m), vid(if std.member(regionsOf(byName[parts[2]]), r) then r else regionsOf(byName[parts[2]])[0], byName[parts[2]]), parts[0], {
        label: parts[1],
        display: { style: if parts[0] == 'mounts' then 'dashed' else 'dotted', tone: if parts[0] == 'mounts' then 'info' else 'warning', directed: true },
      })
      for r in regionNames
      for m in inRegion(r)
      for link in std.split(ann(m.obj, 'links', ''), ';')
      if link != '' && std.objectHas(byName, std.split(link, '|')[2])
    ];
    // The shared resources' two visual instances are tied by a same-resource link.
    local sameEdges = [
      view.edge('same/' + m.obj.metadata.uid, vid(regionsOf(m)[0], m), vid(regionsOf(m)[1], m), 'same-resource', { label: 'same UID', display: { style: 'dotted', tone: 'neutral', directed: false } })
      for m in sorted
      if std.length(regionsOf(m)) > 1
    ];

    view.scene(
      ['demo'],
      view.merge([rootNode] + [regionNode(r) for r in regionNames] + [memberNode(r, m) for r in regionNames for m in inRegion(r)]),
      ownership + linkEdges + sameEdges,
      {
        title: 'Graph demo (' + ctx.scope.namespace + ')',
        zoom: view.zoom([
          view.step(0, [1], { id: 'namespace', label: 'Namespace', statusSeverity: 7 }),
          view.step(1, [1, 1], { id: 'regions', label: 'Regions', statusSeverity: 5 }),
          view.step(2, [1, 1, 0], { id: 'members', label: 'Members', statusSeverity: 3 }),
          view.step(2, [1, 1, 1], { id: 'details', label: 'Details', statusSeverity: 1 }),
          view.step(2, [2, 2, 2], { id: 'full', label: 'Full cards', statusSeverity: 0 }),
        ], 2),
        display: view.display([
          view.filter('tier', 'Tier', 'tier', [view.option(t, t) for t in tiers], ['root', 'leaf', 'agent']),
          view.filter('kind', 'Kind', 'kind', [view.option('ConfigMap', 'ConfigMap'), view.option('Agent', 'Agent')]),
        ], 'tree'),
      }
    ),
}
