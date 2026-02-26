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
    parser = argparse.ArgumentParser(description="Count app-to-app switches from Chronicle CSV.")
    parser.add_argument("--csv", required=True, help="Path to Chronicle CSV export.")
    parser.add_argument("--max-gap", type=int, default=120, help="Max seconds between rows to count a direct switch.")
    parser.add_argument("--top", type=int, default=30, help="How many transitions to print.")
    args = parser.parse_args()

    rows = []
    with open(args.csv, "r", encoding="utf-8", newline="") as handle:
        reader = csv.DictReader(handle)
        for row in reader:
            if is_idle(row.get("is_idle", "0")):
                continue
            app_name = (row.get("app_name") or "").strip()
            if not app_name:
                continue
            start = parse_int(row.get("start_time", "0"))
            end = parse_int(row.get("end_time", "0"))
            if end <= start:
                continue
            rows.append((start, end, app_name))

    rows.sort(key=lambda item: item[0])

    transitions = defaultdict(int)
    for previous, current in zip(rows, rows[1:]):
        prev_start, prev_end, prev_app = previous
        curr_start, _, curr_app = current
        if prev_app == curr_app:
            continue
        gap = curr_start - prev_end
        if gap < 0 or gap > args.max_gap:
            continue
        transitions[(prev_app, curr_app)] += 1

    ordered = sorted(transitions.items(), key=lambda item: item[1], reverse=True)
    print("from_app,to_app,switch_count")
    for (from_app, to_app), count in ordered[: max(1, args.top)]:
        print(f"{from_app},{to_app},{count}")


if __name__ == "__main__":
    main()

