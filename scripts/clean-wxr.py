#!/usr/bin/env python3
"""
Strip spam out of a WordPress WXR export before importing it.

The batchfromscratch.me export is 214MB, of which the actual blog is a rounding
error: 27 published posts, 2 pages and 426 attachments. The rest is 53,690
unapproved spam comments and 13,191 taxonomy terms injected by an "ItemPress"
plugin. Importing it as-is would carry all of that onto the new server, where it
would sit in the moderation queue and the terms tables forever.

What is removed:

  * every comment that is not approved. 53,690 of 53,713 comments are in the
    moderation queue and sampling shows them to be pharma, CBD, porn and SEO link
    spam. Anything genuine that was awaiting moderation for eight years is a loss
    worth taking; --keep-unapproved is there if you disagree.
  * the itempress_tag, itempress_category and monsterinsights_note_category
    taxonomies. itempress_tag holds 13,191 terms with names like
    "( 1 ) 10.6 Ounce Box" — product descriptors from an affiliate plugin that has
    no business on a recipe blog.
  * the "! Без рубрики" and "Artificial intelligence (AI)" categories, which hold
    no posts and are the standard fingerprint of an SEO injection.

What is kept, deliberately:

  * drafts. There are five from March 2017 that were never published; they are the
    author's to delete, not this script's.
  * approved comments, all 23, including one that looks like spam that slipped
    through moderation. Flagged in the report rather than removed, because the
    difference between "reads like spam" and "is spam" is a judgement call and 23
    is a small enough number to eyeball.

Usage:
    python3 scripts/clean-wxr.py export.xml cleaned.xml
"""

from __future__ import annotations

import argparse
import re
import sys
import xml.etree.ElementTree as ET
from collections import Counter

WP = "{http://wordpress.org/export/1.2/}"

NAMESPACES = {
    "excerpt": "http://wordpress.org/export/1.2/excerpt/",
    "content": "http://purl.org/rss/1.0/modules/content/",
    "wfw": "http://wellformedweb.org/CommentAPI/",
    "dc": "http://purl.org/dc/elements/1.1/",
    "wp": "http://wordpress.org/export/1.2/",
}

# Taxonomies that exist only because a plugin put them there.
JUNK_TAXONOMIES = {
    "itempress_tag",
    "itempress_category",
    "monsterinsights_note_category",
}

# Categories by slug that carry no posts and are characteristic of SEO injection.
JUNK_CATEGORY_SLUGS = {
    "bez-rubriki",
    "artificial-intelligence-ai",
}

# Only used to annotate the report — nothing is removed on the strength of it.
SPAM_HINTS = re.compile(
    r"\b(cbd|viagra|cialis|casino|porn|escort|payday|crypto|seo services|"
    r"erectile|pharmac|chloroquine)\b",
    re.I,
)


def text(el: ET.Element, tag: str) -> str:
    return (el.findtext(tag) or "").strip()


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("source")
    ap.add_argument("destination")
    ap.add_argument("--keep-unapproved", action="store_true",
                    help="retain comments awaiting moderation (they are almost all spam)")
    ap.add_argument("--drop-drafts", action="store_true",
                    help="also remove unpublished drafts")
    args = ap.parse_args()

    for prefix, uri in NAMESPACES.items():
        ET.register_namespace(prefix, uri)

    stats: Counter = Counter()
    kept_comments: list[tuple[str, str, str, str]] = []
    junk_term_ids: set[str] = set()

    context = ET.iterparse(args.source, events=("start", "end"))
    _, root = next(context)

    channel = None

    for event, el in context:
        if event == "start":
            if el.tag == "channel" and channel is None:
                channel = el
            continue

        # ---- channel-level taxonomy terms ---------------------------------
        if el.tag in (WP + "term", WP + "category", WP + "tag"):
            taxonomy = text(el, WP + "term_taxonomy")
            slug = text(el, WP + "term_slug") or text(el, WP + "category_nicename")

            drop = taxonomy in JUNK_TAXONOMIES or slug in JUNK_CATEGORY_SLUGS
            if drop:
                term_id = text(el, WP + "term_id")
                if term_id:
                    junk_term_ids.add(term_id)
                stats[f"terms removed ({taxonomy or 'category'})"] += 1
                el.clear()
                if channel is not None:
                    channel.remove(el)
            else:
                stats[f"terms kept ({taxonomy or 'category'})"] += 1
            continue

        # ---- term metadata belonging to removed terms ----------------------
        if el.tag == WP + "termmeta":
            # termmeta sits inside its term, so it leaves with the parent. Nothing
            # to do here beyond counting what was in the file.
            stats["termmeta seen"] += 1
            continue

        if el.tag != "item":
            continue

        # ---- posts, pages and attachments ---------------------------------
        post_type = text(el, WP + "post_type")
        status = text(el, WP + "status")
        title = text(el, "title")

        if args.drop_drafts and post_type == "post" and status == "draft":
            stats["drafts removed"] += 1
            el.clear()
            channel.remove(el)
            continue

        # Comments.
        for comment in el.findall(WP + "comment"):
            approved = text(comment, WP + "comment_approved")
            if approved == "1" or args.keep_unapproved:
                stats["comments kept"] += 1
                body = text(comment, WP + "comment_content")
                kept_comments.append((
                    text(comment, WP + "comment_author"),
                    text(comment, WP + "comment_author_url"),
                    title,
                    body,
                ))
            else:
                stats["comments removed"] += 1
                el.remove(comment)

        # Category/tag references pointing at taxonomies we just deleted. Left
        # behind, the importer would helpfully recreate every one of them.
        for ref in el.findall("category"):
            domain = ref.get("domain", "")
            nicename = ref.get("nicename", "")
            if domain in JUNK_TAXONOMIES or nicename in JUNK_CATEGORY_SLUGS:
                stats["category references removed"] += 1
                el.remove(ref)

        stats[f"items kept ({post_type or 'unknown'}/{status or '-'})"] += 1

    tree = ET.ElementTree(root)
    ET.indent(tree, space="\t")
    tree.write(args.destination, encoding="UTF-8", xml_declaration=True)

    # ---- report -----------------------------------------------------------
    print("Cleaned WXR written to", args.destination, file=sys.stderr)
    print(file=sys.stderr)
    for key in sorted(stats):
        print(f"  {stats[key]:>7}  {key}", file=sys.stderr)

    suspicious = [c for c in kept_comments if SPAM_HINTS.search(c[3]) or
                  (c[1] and SPAM_HINTS.search(c[1]))]
    if suspicious:
        print(f"\n  {len(suspicious)} kept comment(s) read like spam — worth a look:",
              file=sys.stderr)
        for author, url, on_post, body in suspicious:
            print(f"    {author!r} on {on_post!r}", file=sys.stderr)
            print(f"      url: {url or '(none)'}", file=sys.stderr)
            print(f"      {body[:160]}", file=sys.stderr)

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
