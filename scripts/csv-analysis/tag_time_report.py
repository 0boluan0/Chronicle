#!/usr/bin/env python3

import argparse
import csv
from collections import defaultdict


def parse_int(value: str) -> int:
    try:
        return int(value)
    except (TypeError, ValueError):
        return 0


def is_idle(value: str) -> bool:
    return str(value).strip().lower() in {"1", "true", "yes"}


def main() -> None:
    parser = argparse.ArgumentParser(description="Summarize active time by tag from Chronicle CSV.")
    parser.add_argument("--csv", required=True, help="Path to Chronicle CSV export.")
    parser.add_argument("--top", type=int, default=20, help="How many tags to print.")
    args = parser.parse_args()

    tag_seconds = defaultdict(int)
    tag_sessions = defaultdict(int)
    total_active = 0

    with open(args.csv, "r", encoding="utf-8", newline="") as handle:
        reader = csv.DictReader(handle)
        for row in reader:
            if is_idle(row.get("is_idle", "0")):
                continue
            duration = parse_int(row.get("duration", "0"))
            if duration <= 0:
                continue
            tag_name = (row.get("effective_tag_name") or row.get("tag_name") or "Untagged").strip() or "Untagged"
            tag_seconds[tag_name] += duration
            tag_sessions[tag_name] += 1
            total_active += duration

    ordered = sorted(tag_seconds.items(), key=lambda item: item[1], reverse=True)
    print("tag,sessions,active_hours,share_percent")
    for tag_name, seconds in ordered[: max(1, args.top)]:
        sessions = tag_sessions[tag_name]
        hours = seconds / 3600.0
        share = (seconds / total_active * 100.0) if total_active else 0.0
        print(f"{tag_name},{sessions},{hours:.2f},{share:.1f}")


if __name__ == "__main__":
    main()

