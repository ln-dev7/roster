#!/usr/bin/env python3
"""Adds one release to Sparkle's update feed.

Called by release.sh; usable by hand if a release ever has to be repaired.

    python3 scripts/make-appcast.py \\
        --appcast site/public/appcast.xml \\
        --version 3 --short-version 0.2.0 \\
        --length 4812345 --signature 'base64…' \\
        --url https://github.com/…/Roster.dmg

Newest item first. An existing item with the same version is replaced rather
than duplicated, so re-running after a botched release repairs the feed
instead of corrupting it.
"""

import argparse
import sys
import xml.dom.minidom as dom
from datetime import datetime, timezone
from email.utils import format_datetime


def strip_whitespace(node):
    """Removes text nodes that are only indentation, recursively."""
    for child in list(node.childNodes):
        if child.nodeType == child.TEXT_NODE and not child.data.strip():
            node.removeChild(child)
        elif child.hasChildNodes():
            strip_whitespace(child)


def find_channel(document):
    channels = document.getElementsByTagName("channel")
    if not channels:
        sys.exit("No <channel> in the appcast — is the file intact?")
    return channels[0]


def existing_item(channel, version):
    """An item already describing this build, if the feed has one."""
    for item in channel.getElementsByTagName("item"):
        nodes = item.getElementsByTagName("sparkle:version")
        if nodes and nodes[0].firstChild and nodes[0].firstChild.data.strip() == version:
            return item
    return None


def text_element(document, name, value):
    element = document.createElement(name)
    element.appendChild(document.createTextNode(value))
    return element


def build_item(document, args, published):
    item = document.createElement("item")
    item.appendChild(text_element(document, "title", args.short_version))
    item.appendChild(text_element(document, "pubDate", published))
    item.appendChild(text_element(document, "sparkle:version", args.version))
    item.appendChild(text_element(document, "sparkle:shortVersionString", args.short_version))
    item.appendChild(text_element(document, "sparkle:minimumSystemVersion", args.minimum_system))

    if args.notes:
        description = document.createElement("description")
        description.appendChild(document.createCDATASection(args.notes))
        item.appendChild(description)

    enclosure = document.createElement("enclosure")
    enclosure.setAttribute("url", args.url)
    enclosure.setAttribute("length", str(args.length))
    enclosure.setAttribute("type", "application/octet-stream")
    # Without a signature that verifies against SUPublicEDKey, Sparkle refuses
    # the update. That is the point of the whole key ceremony.
    enclosure.setAttribute("sparkle:edSignature", args.signature)
    item.appendChild(enclosure)

    return item


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--appcast", required=True)
    parser.add_argument("--version", required=True, help="CFBundleVersion, the build number")
    parser.add_argument("--short-version", required=True, help="MARKETING_VERSION, e.g. 0.2.0")
    parser.add_argument("--length", required=True)
    parser.add_argument("--signature", required=True)
    parser.add_argument("--url", required=True)
    parser.add_argument("--minimum-system", default="14.0")
    parser.add_argument("--notes", default="")
    parser.add_argument("--date", default=None,
                        help="RFC 2822 date; defaults to now, in UTC")
    args = parser.parse_args()

    if not args.signature or args.signature.startswith("--"):
        sys.exit("Refusing to write an item without a real signature.")

    document = dom.parse(args.appcast)
    channel = find_channel(document)
    published = args.date or format_datetime(datetime.now(timezone.utc))

    old = existing_item(channel, args.version)
    if old is not None:
        channel.removeChild(old)
        print(f"  replaced the existing item for build {args.version}")

    item = build_item(document, args, published)

    # Newest first: insert before the first existing item, or append when the
    # feed is still empty.
    items = channel.getElementsByTagName("item")
    if items:
        channel.insertBefore(item, items[0])
    else:
        channel.appendChild(item)

    # minidom keeps the old indentation as text nodes and adds its own on top,
    # so the file grows a new layer of blank lines at every release. Drop the
    # whitespace first and let it re-indent from scratch: the feed then stays
    # reviewable in a diff, which matters for the one file that decides what
    # every installed copy downloads.
    strip_whitespace(document)
    xml = document.toprettyxml(indent="  ", encoding="utf-8").decode("utf-8")
    xml = "\n".join(line for line in xml.splitlines() if line.strip())
    with open(args.appcast, "w", encoding="utf-8") as handle:
        handle.write(xml.rstrip() + "\n")

    print(f"  {args.short_version} (build {args.version}) added to {args.appcast}")
    print(f"  {args.url}")


if __name__ == "__main__":
    main()
