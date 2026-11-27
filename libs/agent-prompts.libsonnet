// The private prompt ConfigMaps of one Agent or ClusterAgent: the text that used to be inline in spec.prompts,
// spec.compaction.prompts and spec.smart_compaction_prompts. Identity, labels and names follow one formula so the
// owner and its ConfigMaps agree without storing anything but the labels:
//   H = sha256(kind '/' namespace '/' name), namespace is '' for a ClusterAgent
//   labels egregon.ai/prompt-owner-kind (agent|clusteragent), prompt-owner-hash-0 (H[0:32]), prompt-owner-hash-1 (H[32:64]), prompt-family (normal|summary|smart)
//   ConfigMap name egregon-ap-<a|c>-<n|s|m>-<H[0:32]>.<H[32:64]>
// The selector of a family selects by all four labels and is required: an Agent never composes without its own text.
local familyInfo = {
  normal: { code: 'n' },
  summary: { code: 's' },
  smart: { code: 'm' },
};
local kindInfo = {
  Agent: { label: 'agent', code: 'a' },
  ClusterAgent: { label: 'clusteragent', code: 'c' },
};
{
  // kind: 'Agent' or 'ClusterAgent'; namespace: the Agent's namespace (null for a ClusterAgent);
  // configmap_namespace: where the ConfigMaps live (the Agent's namespace, or the ClusterAgent's sandbox namespace);
  // families: { normal, summary, smart } maps data key -> text, an empty map renders nothing for that family.
  // Returns { config_maps: [ConfigMap], selectors: { <family>: { parts: <required selector> } } }; the selectors of an empty family are {}.
  bundle(kind, name, namespace, configmap_namespace, families, annotations={})::
    local hash = std.sha256(kind + '/' + (if namespace == null then '' else namespace) + '/' + name);
    local hash0 = std.substr(hash, 0, 32);
    local hash1 = std.substr(hash, 32, 32);
    local nonempty = [f for f in std.objectFields(familyInfo) if std.length(std.get(families, f, {})) > 0];
    local labelsOf(family) = {
      'egregon.ai/prompt-owner-kind': kindInfo[kind].label,
      'egregon.ai/prompt-owner-hash-0': hash0,
      'egregon.ai/prompt-owner-hash-1': hash1,
      'egregon.ai/prompt-family': family,
    };
    {
      config_maps: [
        {
          apiVersion: 'v1',
          kind: 'ConfigMap',
          metadata: {
            name: 'egregon-ap-' + kindInfo[kind].code + '-' + familyInfo[f].code + '-' + hash0 + '.' + hash1,
            namespace: configmap_namespace,
            labels: labelsOf(f),
            annotations: annotations { 'egregon.ai/prompt-owner': kind + '/' + (if namespace == null then '' else namespace) + '/' + name },
          },
          data: families[f],
        }
        for f in nonempty
      ],
      selectors: {
        [f]: if std.member(nonempty, f) then { parts: { namespace: configmap_namespace, matchLabels: labelsOf(f), required: true } } else {}
        for f in std.objectFields(familyInfo)
      },
    },

  // The external selectors a caller supplies keep selecting live ConfigMaps; their key S becomes parts.S so that every part name is parts.<former name>.
  renameSelectors(selectors):: if selectors == null then {} else { ['parts.' + s]: selectors[s] for s in std.objectFields(selectors) },
}
