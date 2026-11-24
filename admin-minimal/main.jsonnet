// The minimal administrator of a Workspace: one Agent with its Sandbox and a personal grant of the Agent identity
// to the ClusterRole egregon-workspace-admin, which tenant-defaults owns. Output names derive from instance_id alone.
local egregon = import '../libs/egregon.libsonnet';
local k8s = import '../libs/k8s.libsonnet';

local workspace = std.extVar('workspace');
local sandboxImage = std.extVar('sandbox_image');
local namespace = 'default';

function(route_kind, route_name, model, instance_id, route_namespace='')
  local name = 'adm-' + instance_id;
  local principal = egregon.principal(workspace, namespace, name);
  [
    egregon.sandbox(name, namespace, sandboxImage, wave=1),
    egregon.agent(
      name,
      namespace,
      model=model,
      route={ kind: route_kind, name: route_name } + (if route_kind == 'Route' then { namespace: route_namespace } else {}),
      sandbox_name=name,
      prompts={
        '0-agent-address': 'Your Egregon agent address is `' + namespace + '/' + name + '` (CLI: `--namespace ' + namespace + ' --name ' + name + '`).',
        '00-role': 'You are the administrator Agent of this Egregon Workspace. Your owner has not written your instructions yet; help configure this Workspace as asked.',
        '10-echo': 'To show a person a file or report in their chat, publish it with `egregon echo --kind media|pdf|markdown|other --description "<short text>" (--file <path> | --content <text>)`; `egregon help echo` has the details. The publication appears in the chat after the current tool batch finishes and you see only its description and an id, never its content.',
      },
      annotations={
        'egregon.ai/show-in-ui': 'true',
        'egregon.ai/display-name': 'Admin',
      },
    ),
    k8s.clusterRoleBinding(name, 'egregon-workspace-admin', sa=null, namespace=null) {
      metadata+: { annotations: { 'egregon.ai/sync-wave': '0' } },
      subjects: [{ apiGroup: 'rbac.authorization.k8s.io', kind: 'User', name: principal }],
    },
  ]
