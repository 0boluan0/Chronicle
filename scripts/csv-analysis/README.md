# Chronicle CSV Analysis Examples

These scripts are local-first examples for analyzing Chronicle CSV exports.
All scripts use only the Python standard library.

## Expected CSV columns

The scripts expect Chronicle CSV exports with at least:

- `start_time`
- `end_time`
- `duration`
- `app_name`
- `is_idle`

For tag-level analysis, include:

- `effective_tag_name` (preferred)
- `tag_name` (fallback)

## Usage

Run from repo root:

```bash
python3 scripts/csv-analysis/tag_time_report.py --csv /path/to/chronicle.csv
python3 scripts/csv-analysis/switch_transition_report.py --csv /path/to/chronicle.csv
python3 scripts/csv-analysis/focus_block_report.py --csv /path/to/chronicle.csv
```

Each script has `--help` for options.

