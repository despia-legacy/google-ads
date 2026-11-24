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

    def test_ios_pins_complete_swiftpm_graph(self):
        spec = self.expand("ios")
        ios = spec["extensions"][0]["ios"]
        pins = ios["swiftpm_pins"]
        resolved = json.loads((ROOT / "googleads/ios/Package.resolved").read_text())
        self.assertEqual(len(resolved["pins"]), len(pins))
        self.assertEqual("13.2.0", pins["firebase-ios-sdk"]["version"])
        self.assertEqual("efad2b784dfae43404dc1fcfdf272981b235e71f", pins["firebase-ios-sdk"]["revision"])
        self.assertEqual({}, ios["pods_closure"])
        manifest = json.loads((ROOT / "googleads/manifest.json").read_text())
        products = [p for pkg in manifest["ios"]["packages"] for p in pkg["products"]]
        self.assertEqual(["FirebaseCore", "FirebaseAnalytics"], products)

    def test_android_uses_custom_module(self):
        spec = self.expand("android")
        self.assertEqual("despia.ext.googleads.GoogleAdsExtension", spec["extensions"][0]["android"]["entry_class"])

    def test_source_passes_existing_initializer_admission(self):
        for platform, pattern in [("ios", "*.swift"), ("android", "*.java")]:
            sources = [("googleads", str(p.relative_to(ROOT)), p.read_text())
                       for p in (ROOT / "googleads" / platform).rglob(pattern)]
            nx_builtins.check_single_init(platform, sources, self.expand(platform))

    def test_unpinned_remote_package_is_refused(self):
        manifest = json.loads((ROOT / "googleads/manifest.json").read_text())
        remotes = [dict(p["remote"], name=p["name"]) for p in manifest["ios"]["packages"]]
        resolved = json.loads((ROOT / "googleads/ios/Package.resolved").read_text())
        resolved["pins"] = [p for p in resolved["pins"] if p["identity"] != "firebase-ios-sdk"]
        with self.assertRaises(NXError) as caught:
            nx_deps.check_swiftpm(resolved, remotes)
        self.assertEqual("NX-D024", caught.exception.code)

    def test_changed_package_revision_stays_refused(self):
        manifest = json.loads((ROOT / "googleads/manifest.json").read_text())
        remotes = [dict(p["remote"], name=p["name"]) for p in manifest["ios"]["packages"]]
        remotes[0]["revision"] = "0" * 40
        resolved = json.loads((ROOT / "googleads/ios/Package.resolved").read_text())
        with self.assertRaises(NXError) as caught:
            nx_deps.check_swiftpm(resolved, remotes)
        self.assertEqual("NX-D024", caught.exception.code)

if __name__ == "__main__":
    unittest.main()
