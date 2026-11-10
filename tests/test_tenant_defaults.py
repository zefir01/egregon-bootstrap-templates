"""Offline checks of the tenant-defaults source: outputs, the narrow data grant and the bucket spec."""
import json
from pathlib import Path
import subprocess
import unittest

SOURCE = Path(__file__).resolve().parents[1] / 'tenant-defaults' / 'main.jsonnet'
BUCKET_VERBS = ['get', 'list_objects', 'get_object', 'get_object_version', 'put_object']


def render():
    return json.loads(subprocess.check_output(['jsonnet', str(SOURCE)], stderr=subprocess.PIPE))


def by_kind():
    return {o['kind']: o for o in render() if o['metadata']['name'] in ('files', 'files-bucket-data-access')}


def by_name(kind, name):
    return next(o for o in render() if o['kind'] == kind and o['metadata']['name'] == name)


class TenantDefaultsTemplate(unittest.TestCase):
    def test_outputs_are_the_bucket_and_its_narrow_grant_and_cluster_scoped(self):
        objects = render()
        self.assertEqual(sorted((o['kind'], o['metadata']['name']) for o in objects), [
            ('ClusterBucket', 'files'),
            ('ClusterRole', 'files-bucket-data-access'),
            ('ClusterRole', 'skills-mcp-access'),
            ('ClusterRole', 'template-runs-mcp-access'),
            ('ClusterRoleBinding', 'files-bucket-data-access'),
            ('ClusterRoleBinding', 'skills-mcp-access'),
            ('ClusterRoleBinding', 'template-runs-mcp-access'),
        ])
        for o in objects:
            self.assertNotIn('namespace', o['metadata'])
            self.assertNotIn('uid', o['metadata'])
            self.assertNotIn('ownerReferences', o['metadata'])

    def test_bucket_spec_fragment_is_explicit_and_has_no_lifecycle(self):
        bucket = by_kind()['ClusterBucket']
        self.assertEqual(bucket['apiVersion'], 'egregon.ai/v1alpha1')
        self.assertEqual(bucket['metadata']['name'], 'files')
        self.assertEqual(bucket['spec'], {
            'presigned_url': {'max_ttl': '24h'},
            'versioning': {'status': 'Enabled'},
            'object_lock': {'enabled': False},
        })

    def test_grant_is_exactly_the_five_data_verbs_on_the_one_bucket_for_authenticated(self):
        objects = by_kind()
        role, binding = objects['ClusterRole'], objects['ClusterRoleBinding']
        self.assertEqual(role['rules'], [{
            'apiGroups': ['egregon.ai'], 'resources': ['clusterbuckets'],
            'resourceNames': ['files'], 'verbs': BUCKET_VERBS,
        }])
        self.assertNotIn('*', json.dumps(role['rules']))
        self.assertEqual(binding['subjects'], [{
            'apiGroup': 'rbac.authorization.k8s.io', 'kind': 'Group', 'name': 'system:authenticated'}])
        self.assertEqual(binding['roleRef'], {
            'apiGroup': 'rbac.authorization.k8s.io', 'kind': 'ClusterRole', 'name': role['metadata']['name']})
        self.assertEqual(binding['metadata']['name'], role['metadata']['name'])

    def test_files_objects_are_unchanged(self):
        objects = by_kind()
        self.assertEqual(objects['ClusterRole']['metadata'], {
            'name': 'files-bucket-data-access', 'annotations': {'egregon.ai/sync-wave': '-2'}})
        self.assertEqual(objects['ClusterRoleBinding']['metadata'], {
            'name': 'files-bucket-data-access', 'annotations': {'egregon.ai/sync-wave': '-1'}})
        self.assertEqual(objects['ClusterBucket']['metadata'], {
            'name': 'files', 'annotations': {'egregon.ai/sync-wave': '0'}})

    def test_skills_mcp_grant_is_exactly_use_of_the_one_clustermcp_for_authenticated(self):
        role = by_name('ClusterRole', 'skills-mcp-access')
        binding = by_name('ClusterRoleBinding', 'skills-mcp-access')
        self.assertEqual(role['rules'], [{
            'apiGroups': ['egregon.ai'], 'resources': ['clustermcps'],
            'resourceNames': ['skills'], 'verbs': ['get', 'list_skills', 'read_skill'],
        }])
        self.assertEqual(binding['roleRef'], {
            'apiGroup': 'rbac.authorization.k8s.io', 'kind': 'ClusterRole', 'name': 'skills-mcp-access'})
        self.assertEqual(binding['subjects'], [{
            'apiGroup': 'rbac.authorization.k8s.io', 'kind': 'Group', 'name': 'system:authenticated'}])
        self.assertLess(int(role['metadata']['annotations']['egregon.ai/sync-wave']),
                        int(binding['metadata']['annotations']['egregon.ai/sync-wave']))

    def test_sync_waves_order_the_grant_before_the_bucket(self):
        objects = by_kind()
        wave = {k: int(v['metadata']['annotations']['egregon.ai/sync-wave']) for k, v in objects.items()}
        self.assertLess(wave['ClusterRole'], wave['ClusterRoleBinding'])
        self.assertLess(wave['ClusterRoleBinding'], wave['ClusterBucket'])

    def test_source_has_no_external_inputs(self):
        # Libraries are bundled in the repository; rendering needs no parameters or external variables.
        text = SOURCE.read_text()
        for marker in ('std.extVar', 'function('):
            self.assertNotIn(marker, text)


if __name__ == '__main__':
    unittest.main()
