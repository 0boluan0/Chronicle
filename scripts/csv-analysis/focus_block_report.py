#!/usr/bin/env python3

import argparse
import csv
from datetime import datetime


def parse_int(value: str) -> int:
    try:
        return int(value)
    except (TypeError, ValueError):
        return 0


def is_idle(value: str) -> bool:
    return str(value).strip().lower() in {"1", "true", "yes"}


def fmt_ts(ts: int) -> str:
    return datetime.fromtimestamp(ts).strftime("%Y-%m-%d %H:%M")


def main() -> None:
    parser = argparse.ArgumentParser(description="Detect deep-work blocks from Chronicle CSV.")
    parser.add_argument("--csv", required=True, help="Path to Chronicle CSV export.")
    parser.add_argument("--min-minutes", type=int, default=25, help="Minimum block duration in minutes.")
    parser.add_argument("--merge-gap", type=int, default=60, help="Merge consecutive rows if gap <= this value (seconds).")
    args = parser.parse_args()

    min_seconds = max(1, args.min_minutes) * 60

    rows = []
    with open(args.csv, "r", encoding="utf-8", newline="") as handle:
        reader = csv.DictReader(handle)
        for row in reader:
            if is_idle(row.get("is_idle", "0")):
                continue
            start = parse_int(row.get("start_time", "0"))
            end = parse_int(row.get("end_time", "0"))
            if end <= start:
                continue
            tag_name = (row.get("effective_tag_name") or row.get("tag_name") or "Untagged").strip() or "Untagged"
            app_name = (row.get("app_name") or "").strip()
            rows.append((start, end, tag_name, app_name))

    rows.sort(key=lambda item: item[0])

    blocks = []
    current = None
    for start, end, tag_name, app_name in rows:
        if current is None:
            current = {
                "start": start,
                "end": end,
                "tag": tag_name,
                "apps": {app_name} if app_name else set(),
            }
            continue

        same_tag = tag_name == current["tag"]
        gap = start - current["end"]
        if same_tag and 0 <= gap <= args.merge_gap:
            current["end"] = max(current["end"], end)
            if app_name:
                current["apps"].add(app_name)
        else:
            blocks.append(current)
            current = {
                "start": start,
                "end": end,
                "tag": tag_name,
                "apps": {app_name} if app_name else set(),
            }

    if current is not None:
        blocks.append(current)

    filtered = [block for block in blocks if (block["end"] - block["start"]) >= min_seconds]
    filtered.sort(key=lambda block: block["end"] - block["start"], reverse=True)

    print("tag,start,end,duration_minutes,app_count,apps")
    for block in filtered:
        duration_minutes = (block["end"] - block["start"]) / 60.0
        apps = sorted(app for app in block["apps"] if app)
        app_count = len(apps)
        app_list = "|".join(apps)
        print(
            f'{block["tag"]},{fmt_ts(block["start"])},{fmt_ts(block["end"])},{duration_minutes:.1f},{app_count},{app_list}'
        )


if __name__ == "__main__":
    main()

