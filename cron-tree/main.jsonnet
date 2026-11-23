// Cron-controller acceptance (task cron-controller): a tree whose Run renders an idle keeper Agent and an
// enabled-or-suspended Cron that creates Runs of the Template crontest/worker; optionally a Queue with an enqueue Cron.
function(
  namespace,
  name_prefix='tree',
  suspend='false',
  schedule='* * * * *',
  with_queue='false',
  run_agents='1',
  model='gpt-example',
  route_name='openai-shared-pool',
)
  local sandbox = {
    apiVersion: 'egregon.ai/v1alpha1',
    kind: 'Sandbox',
    metadata: { name: name_prefix + '-keeper', namespace: namespace, annotations: {} },
    spec: {
      image: '10.110.153.236:5000/ai-platform/egregon-sandbox-executor:4b490a84a8998e01f7c14fee446299d8db276c84',
      resources: { limits: { cpu: '500m' }, requests: { cpu: '50m' } },
      suspend: false,
      volume_claim: { accessModes: ['ReadWriteOnce'], resources: { requests: { storage: '1Gi' } } },
    },
  };
  local keeper = {
    apiVersion: 'egregon.ai/v1alpha1',
    kind: 'Agent',
    metadata: { name: name_prefix + '-keeper', namespace: namespace, labels: { role: 'keeper', 'acceptance/run': name_prefix }, annotations: {} },
    spec: {
      model: model,
      effort: 'low',
      autostart: false,
      network_policy: {},
      route: { kind: 'ClusterRoute', name: route_name },
      sandbox: { name: name_prefix + '-keeper' },
      prompts: { '00-task': 'CRON-ACC-KEEPER agent=' + name_prefix + '-keeper.' },
    },
  };
  local cron = {
    apiVersion: 'egregon.ai/v1alpha1',
    kind: 'Cron',
    metadata: { name: name_prefix + '-cron', namespace: namespace, annotations: {} },
    spec: {
      schedule: schedule,
      suspend: suspend == 'true',
      action: { create_run: {
        template_ref: { name: 'worker' },
        parameters: { directory: { jsonnet: { tlas: [{ name: 'namespace', value: namespace }, { name: 'name_prefix', value: name_prefix + 'r' }, { name: 'agent_count', value: run_agents }] } } },
        completion_selector: { matchLabels: { role: 'worker' } },
      } },
    },
  };
  local queue = {
    apiVersion: 'egregon.ai/v1alpha1',
    kind: 'Queue',
    metadata: { name: name_prefix + '-q', namespace: namespace, annotations: {} },
    spec: {
      template_ref: { kind: 'Template', name: 'worker' },
      input_selector: { matchLabels: { role: 'input' } },
      max_workers: 1,
      persistent_workers: true,
      parameters: { directory: { jsonnet: { tlas: [{ name: 'namespace', value: namespace }, { name: 'name_prefix', value: name_prefix + 'qw' }, { name: 'role', value: 'input' }, { name: 'autostart', value: 'false' }] } } },
    },
  };
  local qcron = {
    apiVersion: 'egregon.ai/v1alpha1',
    kind: 'Cron',
    metadata: { name: name_prefix + '-qcron', namespace: namespace, annotations: {} },
    spec: { schedule: schedule, suspend: suspend == 'true', action: { enqueue: { name: name_prefix + '-q', text: 'CRON-TREE enqueue ' + name_prefix } } },
  };
  [sandbox, keeper, cron] + (if with_queue == 'true' then [queue, qcron] else [])
