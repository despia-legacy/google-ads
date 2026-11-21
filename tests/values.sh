#!/bin/bash
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
WORK="$(mktemp -d "${TMPDIR:?Set TMPDIR to an approved work directory}/despia-google-ads.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
python3 - "$HERE/../googleads/ios/app/GoogleAdsExtension.swift" "$WORK/Parameters.swift" <<'PYTHON'
from pathlib import Path
import sys
source = Path(sys.argv[1]).read_text()
Path(sys.argv[2]).write_text('import Foundation\nimport CoreFoundation\n' + source[source.index('enum GoogleAdsParameters {'):])
PYTHON
swiftc -swift-version 5 -parse-as-library "$WORK/Parameters.swift" "$HERE/GoogleAdsParametersTests.swift" -o "$WORK/parameters"
"$WORK/parameters"
