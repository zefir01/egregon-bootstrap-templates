// The default transparent view of a Workspace, written against the public view author library like any other view:
// namespaces are regions holding the Runs and Agents of that namespace, ownership is drawn as edges, and every
// region carries the recent telemetry totals of its namespace.
//
// Parameters (execution parameters): recentWindowMinutes, the telemetry window of the aggregates (1..1440).
local view = import 'egregon.ai/view/v1.libsonnet';

local agentFields = [
  '/metadata/ownerReferences',
  '/metadata/creationTimestamp',
  '/metadata/annotations/egregon.ai~1display-name',
  '/status/activity',
];
local runFields = [
  '/metadata/ownerReferences',
  '/metadata/creationTimestamp',
  '/metadata/annotations/egregon.ai~1display-name',
  '/status/health',
];
local kindOrder = { ClusterTemplateRun: 0, TemplateRun: 1, ClusterAgent: 2, Agent: 3 };
local kindResource = { ClusterTemplateRun: 'clustertemplateruns', TemplateRun: 'templateruns', ClusterAgent: 'clusteragents', Agent: 'agents' };

local namespaceOf(o) = std.get(o.metadata, 'namespace', '');
local titleOf(o) = std.get(std.get(o.metadata, 'annotations', {}), 'egregon.ai/display-name', o.metadata.name);
local createdOf(o) = std.get(o.metadata, 'creationTimestamp', '');
local stateOf(o) =
  if std.endsWith(o.kind, 'Agent') then std.get(std.get(std.get(o, 'status', {}), 'activity', {}), 'state', 'Unknown')
  else std.get(std.get(std.get(o, 'status', {}), 'health', {}), 'status', 'Unknown');
local toneOf(o) =
  local state = stateOf(o);
  if state == 'Healthy' then 'success'
  else if state == 'Degraded' || state == 'Missing' then 'danger'
  else if state == 'Progressing' || state == 'Running' then 'info'
  else if state == 'Unknown' then 'muted'
  else 'neutral';
local count(n, noun) = std.toString(n) + ' ' + noun;

{
  inputs(params)::
    {
      namespaces: view.input('', 'namespaces'),
      agents: view.input('egregon.ai', 'agents', { representation: 'full', fields: agentFields }),
      clusteragents: view.input('egregon.ai', 'clusteragents', { representation: 'full', fields: agentFields }),
      templateruns: view.input('egregon.ai', 'templateruns', { representation: 'full', fields: runFields }),
      clustertemplateruns: view.input('egregon.ai', 'clustertemplateruns', { representation: 'full', fields: runFields }),
    },

  render(ctx)::
    local minutes = std.get(ctx.params, 'recentWindowMinutes', 15);
    assert std.isNumber(minutes) && minutes >= 1 && minutes <= 1440 && std.floor(minutes) == minutes :
           'parameter recentWindowMinutes must be a whole number of minutes from 1 to 1440';

    // Two serial aggregate queries over the recent window; each result is bound once, so each query runs once.
    local database = view.telemetry.schema().database;
    local byNamespace =
      view.telemetry.records(view.telemetry.query(
        "SELECT LogAttributes['egregon.namespace.name'] AS namespace, count() AS events, " +
        'countIf(SeverityNumber >= 17) AS errors, countIf(SeverityNumber >= 13 AND SeverityNumber < 17) AS warnings ' +
        'FROM `%s`.otel_logs WHERE Timestamp >= now() - INTERVAL %d MINUTE GROUP BY namespace ORDER BY events DESC LIMIT 500' % [database, minutes]
      ));
    local byCategory =
      view.telemetry.records(view.telemetry.query(
        "SELECT LogAttributes['egregon.category'] AS category, count() AS events " +
        'FROM `%s`.otel_logs WHERE Timestamp >= now() - INTERVAL %d MINUTE GROUP BY category ORDER BY events DESC LIMIT 20' % [database, minutes]
      ));
    local num(v) = std.parseInt(std.toString(v));  // 64-bit counts arrive as strings
    local statsOf = { [r.namespace]: { events: num(r.events), errors: num(r.errors), warnings: num(r.warnings) } for r in byNamespace };
    local noStats = { events: 0, errors: 0, warnings: 0 };
    local statsFor(ns) = std.get(statsOf, ns, noStats);
    local totalEvents = std.foldl(function(a, r) a + num(r.events), byCategory, 0);
    local totalWarnings = std.foldl(function(a, r) a + r.warnings, std.objectValues(statsOf), 0);
    local totalErrors = std.foldl(function(a, r) a + r.errors, std.objectValues(statsOf), 0);
    local eventsText(stats) = 'Events in the last %d min: %d, warnings %d, errors %d' % [minutes, stats.events, stats.warnings, stats.errors];
    local severityTone(stats) = if stats.errors > 0 then 'danger' else if stats.warnings > 0 then 'warning' else 'neutral';

    local resources = std.sort(
      ctx.inputs.templateruns + ctx.inputs.clustertemplateruns + ctx.inputs.agents + ctx.inputs.clusteragents,
      function(o) '%d/%s' % [kindOrder[o.kind], o.metadata.name]
    );
    local visualId(o) = 'res/' + o.metadata.uid;
    local namespaces = std.sort(ctx.inputs.namespaces, function(o) o.metadata.name);
    local inNamespace(ns) = [o for o in resources if namespaceOf(o) == ns];
    local clusterScoped = inNamespace('');
    local agentsIn(list) = std.length([o for o in list if std.endsWith(o.kind, 'Agent')]);
    local runsIn(list) = std.length(list) - agentsIn(list);
    local countsText(list) = count(agentsIn(list), 'agents') + ' · ' + count(runsIn(list), 'runs');

    local resourceNode(o) = view.node(visualId(o), titleOf(o), {
      kind: o.kind,
      tone: toneOf(o),
      resourceRef: view.resourceRef(o, kindResource[o.kind]),
      card: view.card(
        [
          view.line('state', stateOf(o), { label: 'State', tone: toneOf(o) }),
          view.line('created', createdOf(o), { label: 'Created' }),
          view.line('owners', std.join(', ', [r.kind + ' ' + r.name for r in std.get(o.metadata, 'ownerReferences', [])]), { label: 'Owned by' }),
        ],
        [['state'], ['state', 'created', 'owners']]
      ),
      panel: view.panelTable(titleOf(o), [
        ['Kind', o.kind],
        ['Name', o.metadata.name],
        ['Namespace', namespaceOf(o)],
        ['UID', o.metadata.uid],
        ['Created', createdOf(o)],
        ['State', stateOf(o)],
      ]),
      facets: { kind: [o.kind], namespace: [namespaceOf(o)] },
    });

    local regionNode(id, title, list, stats, ref, facetValue) = view.node(id, title, {
      kind: if ref == null then 'Cluster-scoped' else 'Namespace',
      tone: severityTone(stats),
      [if ref != null then 'resourceRef']: ref,
      children: [visualId(o) for o in list],
      card: view.card(
        [
          view.line('counts', countsText(list), { label: 'Contents' }),
          view.line('events', eventsText(stats), { label: 'Telemetry', tone: severityTone(stats) }),
        ],
        [['counts'], ['counts', 'events']]
      ),
      panel: view.panelTable(title, [['Contents', countsText(list)], ['Telemetry', eventsText(stats)]]),
      facets: { namespace: [facetValue] },
    });

    local namespaceNodes = [
      regionNode('ns/' + ns.metadata.name, ns.metadata.name, inNamespace(ns.metadata.name), statsFor(ns.metadata.name), view.resourceRef(ns, 'namespaces'), ns.metadata.name)
      for ns in namespaces
    ];
    local clusterNodes = if std.length(clusterScoped) == 0 then [] else [
      regionNode('cluster', 'Cluster-scoped resources', clusterScoped, statsFor(''), null, ''),
    ];
    local regionIds = ['ns/' + ns.metadata.name for ns in namespaces] + (if std.length(clusterNodes) == 0 then [] else ['cluster']);

    local workspaceNode = view.node('ws', 'Workspace', {
      kind: 'Workspace',
      tone: severityTone({ errors: totalErrors, warnings: totalWarnings }),
      children: regionIds,
      card: view.card(
        [
          view.line('summary', count(std.length(namespaces), 'namespaces') + ' · ' + countsText(resources), { label: 'Contents' }),
          view.line('events', eventsText({ events: totalEvents, warnings: totalWarnings, errors: totalErrors }), { label: 'Telemetry' }),
          view.packed('categories', [r.category + ' ' + r.events for r in byCategory], { label: 'By category' }),
        ],
        [['summary'], ['summary', 'events', 'categories']]
      ),
    });

    local known = { [o.metadata.uid]: true for o in resources };
    local edges = [
      view.edge('own/' + ref.uid + '/' + o.metadata.uid, 'res/' + ref.uid, visualId(o), 'ownership', { display: { directed: true } })
      for o in resources
      for ref in std.get(o.metadata, 'ownerReferences', [])
      if std.objectHas(known, ref.uid) && ref.uid != o.metadata.uid
    ];

    view.scene(
      ['ws'],
      view.merge([workspaceNode] + namespaceNodes + clusterNodes + [resourceNode(o) for o in resources]),
      edges,
      {
        title: 'Workspace ' + ctx.scope.workspace,
        zoom: view.zoom([
          view.step(0, [1], { id: 'workspace', label: 'Workspace', statusSeverity: 7 }),
          view.step(1, [1, 1], { id: 'namespaces', label: 'Namespaces', statusSeverity: 5 }),
          view.step(2, [1, 1, 0], { id: 'resources', label: 'Runs and Agents', statusSeverity: 3 }),
          view.step(2, [1, 1, 1], { id: 'details', label: 'Details', statusSeverity: 1 }),
        ], 1),
        display: view.display([
          view.filter('kind', 'Kind', 'kind', [view.option(k, k) for k in ['ClusterTemplateRun', 'TemplateRun', 'ClusterAgent', 'Agent']]),
          view.filter('namespace', 'Namespace', 'namespace', [view.option(ns.metadata.name, ns.metadata.name) for ns in namespaces]),
        ], 'tree'),
      }
    ),
}
