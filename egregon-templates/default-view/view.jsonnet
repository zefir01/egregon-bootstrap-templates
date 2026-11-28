// The default transparent view of a Workspace, written against the public view author library like any other view.
//
// One wildcard METADATA input acquires every list/watch-capable resource of the Workspace through the shared
// input mechanism (Secrets are always bounded metadata); narrow typed inputs add the live state of Agents and Runs.
// Namespaces are regions, each holding one region per resource kind, each holding every acquired object; nothing is
// capped or left out. Ownership is drawn as edges and two serial whole-Workspace aggregate queries over the recent
// telemetry window colour the regions.
//
// The same UID can be listed through several APIs (an Event is served by both `events` and `events.events.k8s.io`).
// This program shows each object once: of all entries sharing a UID it keeps the one whose API reference sorts first,
// before any visual ID is made. The runtime itself never merges anything.
//
// Display filters: every region carries the union of its own and its descendants' facet values, so selecting a Kind
// keeps the Workspace and the namespaces holding it and hides what does not contain it.
//
// Parameters (execution parameters): recentWindowMinutes, the telemetry window of the aggregates (1..1440).
local view = import 'egregon.ai/view/v1.libsonnet';

local wildcardFields = [
  '/metadata/ownerReferences',
  '/metadata/creationTimestamp',
  '/metadata/deletionTimestamp',
  '/metadata/annotations/egregon.ai~1display-name',
];
local primaryResources = ['agents', 'clusteragents', 'templateruns', 'clustertemplateruns'];
local clusterValue = '(cluster)';  // facet value of cluster-scoped objects; no namespace name can contain parentheses

local num(v) = std.parseInt(std.toString(v));  // 64-bit counts arrive as strings
local shortId(s) = if std.length(s) <= 240 then s else std.substr(s, 0, 200) + '#' + std.md5(s);
local nsValue(ns) = if ns == '' then clusterValue else ns;

// runsBy splits an array already sorted by key into [{key, items}] runs of equal key, in one pass.
local runsBy(sorted, keyFn) =
  local keys = [keyFn(x) for x in sorted];
  local n = std.length(sorted);
  local starts = [i for i in std.range(0, n - 1) if i == 0 || keys[i] != keys[i - 1]];
  [
    { key: keys[starts[j]], items: sorted[starts[j]:(if j + 1 < std.length(starts) then starts[j + 1] else n)] }
    for j in std.range(0, std.length(starts) - 1)
  ];

local stateOf(o) =
  if std.endsWith(o.kind, 'Agent') then std.get(std.get(std.get(o, 'status', {}), 'activity', {}), 'state', 'Unknown')
  else std.get(std.get(std.get(o, 'status', {}), 'health', {}), 'status', 'Unknown');
local toneOf(state) =
  if state == 'Healthy' then 'success'
  else if state == 'Degraded' || state == 'Missing' then 'danger'
  else if state == 'Progressing' || state == 'Running' then 'info'
  else if state == 'Unknown' then 'muted'
  else 'neutral';

{
  inputs(params)::
    {
      all: view.input('*', '*', { fields: wildcardFields }),
      agents: view.input('egregon.ai', 'agents', { representation: 'full', fields: ['/status/activity'] }),
      clusteragents: view.input('egregon.ai', 'clusteragents', { representation: 'full', fields: ['/status/activity'] }),
      templateruns: view.input('egregon.ai', 'templateruns', { representation: 'full', fields: ['/status/health'] }),
      clustertemplateruns: view.input('egregon.ai', 'clustertemplateruns', { representation: 'full', fields: ['/status/health'] }),
    },

  render(ctx)::
    local minutes = std.get(ctx.params, 'recentWindowMinutes', 15);
    assert std.isNumber(minutes) && minutes >= 1 && minutes <= 1440 && std.floor(minutes) == minutes :
           'parameter recentWindowMinutes must be a whole number of minutes from 1 to 1440';

    // ---- telemetry: two serial whole-Workspace aggregates; each result is bound once, so each query runs once ----
    local database = view.telemetry.schema().database;
    local byNamespace =
      view.telemetry.records(view.telemetry.query(
        "SELECT LogAttributes['egregon.namespace.name'] AS namespace, count() AS events, " +
        'countIf(SeverityNumber >= 17) AS errors, countIf(SeverityNumber >= 13 AND SeverityNumber < 17) AS warnings ' +
        'FROM `%s`.otel_logs WHERE Timestamp >= now() - INTERVAL %d MINUTE GROUP BY namespace ORDER BY events DESC' % [database, minutes]
      ));
    local byCategory =
      view.telemetry.records(view.telemetry.query(
        "SELECT LogAttributes['egregon.category'] AS category, count() AS events " +
        'FROM `%s`.otel_logs WHERE Timestamp >= now() - INTERVAL %d MINUTE GROUP BY category ORDER BY events DESC' % [database, minutes]
      ));
    local statsOf = { [r.namespace]: { events: num(r.events), errors: num(r.errors), warnings: num(r.warnings) } for r in byNamespace };
    local noStats = { events: 0, errors: 0, warnings: 0 };
    local statsFor(ns) = std.get(statsOf, ns, noStats);
    local totalEvents = std.foldl(function(a, r) a + num(r.events), byCategory, 0);
    local totalWarnings = std.foldl(function(a, r) a + r.warnings, std.objectValues(statsOf), 0);
    local totalErrors = std.foldl(function(a, r) a + r.errors, std.objectValues(statsOf), 0);
    local eventsText(stats) = 'Events in the last %d min: %d, warnings %d, errors %d' % [minutes, stats.events, stats.warnings, stats.errors];
    local severityTone(stats) = if stats.errors > 0 then 'danger' else if stats.warnings > 0 then 'warning' else 'neutral';

    // ---- one entry per UID, chosen before any visual ID exists ----
    local uidOf(e) = e.object.metadata.uid;
    local refKey(r) = '%s/%s/%s/%s/%s' % [r.group, r.version, r.resource, std.get(r, 'namespace', ''), r.name];
    local byUid = std.sort(view.entries(ctx, 'all'), function(e) [uidOf(e), refKey(e.resourceRef)]);
    local chosen = [byUid[i] for i in std.range(0, std.length(byUid) - 1) if i == 0 || uidOf(byUid[i - 1]) != uidOf(byUid[i])];

    // The live state of Agents and Runs enriches the chosen entry; the wildcard reference stays the node's identity.
    local typedByUid = {
      [o.metadata.uid]: o
      for o in ctx.inputs.agents + ctx.inputs.clusteragents + ctx.inputs.templateruns + ctx.inputs.clustertemplateruns
    };
    local records = [
      {
        uid: uidOf(e),
        ref: e.resourceRef,
        object: e.object,
        ns: std.get(e.resourceRef, 'namespace', ''),
        kind: e.object.kind,
        gr: if e.resourceRef.group == '' then e.resourceRef.resource else e.resourceRef.resource + '.' + e.resourceRef.group,
        primary: e.resourceRef.group == 'egregon.ai' && std.member(primaryResources, e.resourceRef.resource),
        typed: std.get(typedByUid, uidOf(e), null),
        title: std.substr(std.get(std.get(e.object.metadata, 'annotations', {}), 'egregon.ai/display-name', e.object.metadata.name), 0, 240),
      }
      for e in chosen
    ];
    local isNamespace(r) = r.ref.group == '' && r.ref.resource == 'namespaces';
    local namespaceRecords = { [r.object.metadata.name]: r for r in records if isNamespace(r) };
    local rank(r) = if r.primary then 0 else 1;
    local leaves = std.sort([r for r in records if !isNamespace(r)], function(r) [r.ns, rank(r), r.gr, r.object.metadata.name, r.uid]);

    // ---- regions: namespace (or cluster) > resource kind > object ----
    local kindRegions = [
      local first = run.items[0];
      local agents = std.length([r for r in run.items if r.primary && std.endsWith(r.kind, 'Agent')]);
      {
        ns: first.ns,
        gr: first.gr,
        id: shortId('kind/' + first.ns + '/' + first.gr),
        items: run.items,
        kinds: std.set([r.kind for r in run.items]),
        agents: agents,
        runs: std.length([r for r in run.items if r.primary]) - agents,
      }
      for run in runsBy(leaves, function(r) [r.ns, rank(r), r.gr])
    ];
    local regionsByNs = { [c.key]: c.items for c in runsBy(kindRegions, function(k) k.ns) };
    local containerOf(ns) =
      local regions = std.get(regionsByNs, ns, []);
      local record = std.get(namespaceRecords, ns, null);
      {
        ns: ns,
        record: record,
        id: if record != null then 'res/' + record.uid else if ns == '' then 'cluster' else shortId('ns/' + ns),
        regions: regions,
        total: std.foldl(function(a, k) a + std.length(k.items), regions, 0),
        agents: std.foldl(function(a, k) a + k.agents, regions, 0),
        runs: std.foldl(function(a, k) a + k.runs, regions, 0),
        kinds: std.set(std.flattenArrays([k.kinds for k in regions]) + (if record != null then ['Namespace'] else [])),
      };
    local namespaceNames = std.set(std.objectFields(namespaceRecords) + [ns for ns in std.objectFields(regionsByNs) if ns != '']);
    local containers = [containerOf(ns) for ns in namespaceNames] + (if std.objectHas(regionsByNs, '') then [containerOf('')] else []);

    local countsText(total, kinds, agents, runs) =
      '%d resources in %d kinds · %d agents · %d runs' % [total, kinds, agents, runs];

    local leafNode(r) =
      local state = if r.typed == null then null else stateOf(r.typed);
      local deleting = std.get(r.object.metadata, 'deletionTimestamp', null);
      local created = std.get(r.object.metadata, 'creationTimestamp', '');
      local owners = [o.kind + ' ' + o.name for o in std.get(r.object.metadata, 'ownerReferences', [])];
      local rows =
        [view.line('kind', r.kind, { label: 'Kind' })] +
        (if state != null then [view.line('state', state, { label: 'State', tone: toneOf(state) })] else []) +
        [view.line('created', created, { label: 'Created' })] +
        (if deleting != null then [view.line('deleting', deleting, { label: 'Deleting since', tone: 'warning' })] else []) +
        (if std.length(owners) > 0 then [view.line('owners', std.join(', ', owners), { label: 'Owned by' })] else []);
      local tone = if deleting != null then 'warning' else if state != null then toneOf(state) else 'neutral';
      view.node('res/' + r.uid, r.title, {
        kind: r.kind,
        tone: tone,
        resourceRef: r.ref,
        card: view.card(rows, [[if state != null then 'state' else 'kind'], [row.id for row in rows]]),
        panel: view.panelTable(r.title,
          [['Kind', r.kind], ['API', r.gr + ' (' + r.ref.version + ')'], ['Name', r.object.metadata.name]] +
          (if r.ns != '' then [['Namespace', r.ns]] else []) +
          [['UID', r.uid], ['Created', created]] +
          (if state != null then [['State', state]] else []) +
          (if deleting != null then [['Deleting since', deleting]] else []) +
          (if std.length(owners) > 0 then [['Owned by', std.join(', ', owners)]] else [])),
        facets: { kind: [r.kind], namespace: [nsValue(r.ns)] },
      });

    local kindRegionNode(k) =
      local count = '%d objects' % std.length(k.items);
      view.node(k.id, k.gr, {
        kind: 'Resource kind',
        tone: 'neutral',
        children: ['res/' + r.uid for r in k.items],
        card: view.card(
          [view.line('counts', count, { label: 'Contents' }), view.line('kind', std.join(', ', k.kinds), { label: 'Kind' })],
          [['counts'], ['counts', 'kind']]
        ),
        panel: view.panelTable(k.gr, [['Resource', k.gr], ['Kind', std.join(', ', k.kinds)], ['Objects', count], ['Namespace', if k.ns == '' then 'cluster-scoped' else k.ns]]),
        facets: { kind: k.kinds, namespace: [nsValue(k.ns)] },
      });

    local containerNode(c) =
      local stats = statsFor(c.ns);
      local title = if c.ns == '' then 'Cluster-scoped resources' else c.ns;
      local contents = countsText(c.total, std.length(c.regions), c.agents, c.runs);
      local created = if c.record == null then '' else std.get(c.record.object.metadata, 'creationTimestamp', '');
      local rows =
        [view.line('counts', contents, { label: 'Contents' }), view.line('events', eventsText(stats), { label: 'Telemetry', tone: severityTone(stats) })] +
        (if created != '' then [view.line('created', created, { label: 'Created' })] else []);
      view.node(c.id, title, {
        kind: if c.ns == '' then 'Cluster-scoped' else 'Namespace',
        tone: severityTone(stats),
        [if c.record != null then 'resourceRef']: c.record.ref,
        children: [k.id for k in c.regions],
        card: view.card(rows, [['counts'], [row.id for row in rows]]),
        panel: view.panelTable(title, [['Contents', contents], ['Telemetry', eventsText(stats)]]),
        facets: { kind: c.kinds, namespace: [nsValue(c.ns)] },
      });

    local totalAgents = std.foldl(function(a, c) a + c.agents, containers, 0);
    local totalRuns = std.foldl(function(a, c) a + c.runs, containers, 0);
    local allKinds = std.set(std.flattenArrays([c.kinds for c in containers]));
    local allNamespaceValues = [nsValue(c.ns) for c in containers];
    local workspaceNode = view.node('ws', 'Workspace', {
      kind: 'Workspace',
      tone: severityTone({ errors: totalErrors, warnings: totalWarnings }),
      children: [c.id for c in containers],
      card: view.card(
        [
          view.line('summary', '%d namespaces · %s' % [std.length(namespaceNames), countsText(std.length(leaves), std.length(kindRegions), totalAgents, totalRuns)], { label: 'Contents' }),
          view.line('events', eventsText({ events: totalEvents, warnings: totalWarnings, errors: totalErrors }), { label: 'Telemetry' }),
          view.packed('categories', [r.category + ' ' + r.events for r in byCategory], { label: 'By category' }),
        ],
        [['summary'], ['summary', 'events', 'categories']]
      ),
      facets: { kind: allKinds, namespace: allNamespaceValues },
    });

    // ---- ownership: only owners acquired in this view are drawn ----
    local known = { [r.uid]: true for r in records };
    local edges = [
      view.edge('own/' + owner + '/' + r.uid, 'res/' + owner, 'res/' + r.uid, 'ownership', { display: { directed: true } })
      for r in records
      for owner in std.set([ref.uid for ref in std.get(r.object.metadata, 'ownerReferences', [])])
      if std.objectHas(known, owner) && owner != r.uid
    ];

    local filters = [
      f
      for f in [
        view.filter('kind', 'Kind', 'kind', [view.option(k, k) for k in allKinds]),
        view.filter('namespace', 'Namespace', 'namespace', [view.option(v, if v == clusterValue then 'Cluster-scoped' else v) for v in allNamespaceValues]),
      ]
      if std.length(f.options) > 0
    ];

    view.scene(
      ['ws'],
      view.merge([workspaceNode] + [containerNode(c) for c in containers] + [kindRegionNode(k) for k in kindRegions] + [leafNode(r) for r in leaves]),
      edges,
      {
        title: 'Workspace ' + ctx.scope.workspace,
        zoom: view.zoom([
          view.step(0, [1], { id: 'workspace', label: 'Workspace', statusSeverity: 7 }),
          view.step(1, [1, 1], { id: 'namespaces', label: 'Namespaces', statusSeverity: 5 }),
          view.step(2, [1, 1, 0], { id: 'kinds', label: 'Resource kinds', statusSeverity: 4 }),
          view.step(3, [1, 1, 0, 0], { id: 'resources', label: 'Resources', statusSeverity: 3 }),
          view.step(3, [1, 1, 1, 1], { id: 'details', label: 'Details', statusSeverity: 1 }),
        ], 1),
        display: view.display(filters, 'tree'),
      }
    ),
}
