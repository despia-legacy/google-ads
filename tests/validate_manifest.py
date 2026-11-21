#!/usr/bin/env python3
"""Run with the app repository's scripts/native_ext path as the only argument."""
import json
import pathlib
import sys
import unittest

sys.path.insert(0, sys.argv.pop(1))
import nx_deps
import nx_builtins
import nx_layout
import nx_manifest
from nx_common import NXError

ROOT = pathlib.Path(__file__).resolve().parents[1]
EXPECT = {"client_id": "00000000-0000-4000-8000-000000000001", "ios_bundle_id": "com.despia.test", "android_package": "com.despia.test"}
FILES = {str(p.relative_to(ROOT)) for p in (ROOT / "googleads").rglob("*") if p.is_file()}

class GoogleAdsManifestTests(unittest.TestCase):
    def expand(self, platform):
        return nx_manifest.expand(nx_layout.load(str(ROOT)), platform, FILES, EXPECT, root=str(ROOT))

    def test_ios_pins_complete_pod_closure(self):
        spec = self.expand("ios")
        closure = spec["extensions"][0]["ios"]["pods_closure"]
        self.assertEqual(22, len(closure))
        self.assertEqual("10.29.0", closure["FirebaseAnalytics"]["version"])
        self.assertNotIn("FirebaseMessaging", closure)
        self.assertEqual(9, len({n.split("/")[0] for n in closure}))

    def test_android_uses_custom_module(self):
        spec = self.expand("android")
        self.assertEqual("despia.ext.googleads.GoogleAdsExtension", spec["extensions"][0]["android"]["entry_class"])

    def test_source_passes_existing_initializer_admission(self):
        for platform, pattern in [("ios", "*.swift"), ("android", "*.java")]:
            sources = [("googleads", str(p.relative_to(ROOT)), p.read_text())
                       for p in (ROOT / "googleads" / platform).rglob(pattern)]
            nx_builtins.check_single_init(platform, sources, self.expand(platform))

    def test_missing_tree_pin_is_refused(self):
        manifest = json.loads((ROOT / "googleads/manifest.json").read_text())
        trees = dict(manifest["ios"]["pod_trees"])
        trees.pop("FirebaseCore")
        with self.assertRaises(NXError) as caught:
            nx_deps.check_pods((ROOT / "googleads/ios/Podfile.lock").read_text(), manifest["ios"]["pods"], trees)
        self.assertEqual("NX-D036", caught.exception.code)

    def test_changed_approved_pod_pin_stays_refused(self):
        spec = self.expand("ios")
        closure = spec["extensions"][0]["ios"]["pods_closure"]
        before = (ROOT / "googleads/ios/Podfile.lock").read_text()
        after = before.replace("FirebaseCore (10.29.0)", "FirebaseCore (10.30.0)")
        with self.assertRaises(NXError) as caught:
            nx_deps.verify_pods("", after, closure)
        self.assertEqual("NX-D033", caught.exception.code)

if __name__ == "__main__":
    unittest.main()
