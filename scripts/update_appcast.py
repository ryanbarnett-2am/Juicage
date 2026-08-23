#!/usr/bin/env python3
"""Add a release to appcast.xml, the feed Sparkle polls for updates.

Called by package-release.sh with the version and the output of Sparkle's
sign_update. Regenerating the whole feed each time (rather than appending blindly)
keeps it valid if a release is rebuilt: an existing entry for the same version is
replaced rather than duplicated.
"""
import re
import sys
from datetime import datetime, timezone
from pathlib import Path

REPO = "ryanbarnett-2am/Juicage"
KEEP = 5          # how many past releases stay in the feed
MIN_OS = "13.0"

def main() -> int:
    if len(sys.argv) < 3:
        print("usage: update_appcast.py <version> <sign_update-output>", file=sys.stderr)
        return 2
    version, sig_line = sys.argv[1], sys.argv[2]

    sig = re.search(r'sparkle:edSignature="([^"]+)"', sig_line)
    length = re.search(r'length="(\d+)"', sig_line)
    if not sig or not length:
        print(f"could not parse sign_update output: {sig_line!r}", file=sys.stderr)
        return 1

    url = (f"https://github.com/{REPO}/releases/download/"
           f"v{version}/Juicage-{version}.zip")
    item = f"""    <item>
      <title>{version}</title>
      <pubDate>{datetime.now(timezone.utc).strftime('%a, %d %b %Y %H:%M:%S +0000')}</pubDate>
      <sparkle:version>{version}</sparkle:version>
      <sparkle:shortVersionString>{version}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>{MIN_OS}</sparkle:minimumSystemVersion>
      <sparkle:releaseNotesLink>https://github.com/{REPO}/releases/tag/v{version}</sparkle:releaseNotesLink>
      <enclosure url="{url}" sparkle:edSignature="{sig.group(1)}" length="{length.group(1)}" type="application/octet-stream"/>
    </item>"""

    path = Path("appcast.xml")
    existing = re.findall(r"    <item>.*?</item>", path.read_text(), re.S) if path.exists() else []
    # Drop any previous entry for this version so a rebuild replaces it.
    existing = [i for i in existing
                if f"<sparkle:version>{version}</sparkle:version>" not in i]

    items = "\n".join([item] + existing[:KEEP - 1])
    path.write_text(
        '<?xml version="1.0" encoding="utf-8"?>\n'
        '<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">\n'
        "  <channel>\n"
        "    <title>Juicage</title>\n"
        f"    <link>https://github.com/{REPO}</link>\n"
        "    <description>Usage meter for claude.ai and local models.</description>\n"
        "    <language>en</language>\n"
        f"{items}\n"
        "  </channel>\n"
        "</rss>\n"
    )
    print(f"  appcast.xml now lists {len(existing[:KEEP - 1]) + 1} release(s), newest {version}")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
