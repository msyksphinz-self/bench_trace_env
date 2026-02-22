#!/usr/bin/env python3
"""
Convert Sniper's sim.stats.sqlite3 database to JSON or YAML format.

By default outputs a human-readable "metrics" view that merges the `names` table
(nameid -> objectname, metricname) with the `values` table (nameid, core, value),
so you see keys like "thread.time_by_core[0]": <value> instead of raw nameid pointers.

Usage:
    convert_sniper_sqlite.py <sqlite_file> [--format json|yaml] [--output <output_file>]
    convert_sniper_sqlite.py <sqlite_file> --raw   # include raw tables (nameid etc.) in output
"""

import argparse
import json
import sqlite3
import sys
from pathlib import Path

try:
    import yaml
    HAS_YAML = True
except ImportError:
    HAS_YAML = False


def get_table_schema(cursor, table_name):
    """Get schema information for a table."""
    cursor.execute(f'PRAGMA table_info("{table_name}")')
    return cursor.fetchall()


def get_all_tables(cursor):
    """Get list of all tables in the database."""
    cursor.execute("SELECT name FROM sqlite_master WHERE type='table'")
    return [row[0] for row in cursor.fetchall()]


def convert_value(value):
    """Convert SQLite value to Python native type."""
    if value is None:
        return None
    if isinstance(value, (int, float)):
        return value
    if isinstance(value, str):
        try:
            if '.' in value:
                return float(value)
            return int(value)
        except ValueError:
            return value
    return str(value)


def export_table_data(cursor, table_name):
    """Export all data from a table as a list of dictionaries."""
    cursor.execute(f'SELECT * FROM "{table_name}"')
    columns = [description[0] for description in cursor.description]
    rows = []
    for row in cursor.fetchall():
        row_dict = {}
        for col, val in zip(columns, row):
            row_dict[col] = convert_value(val)
        rows.append(row_dict)
    return rows


def build_resolved_metrics(cursor):
    """
    Merge `names` (nameid -> objectname, metricname) and `values` (prefixid, nameid, core, value)
    so that output is keyed by "objectname.metricname[core]" -> value per prefix.
    """
    # nameid -> (objectname, metricname)
    cursor.execute('SELECT nameid, objectname, metricname FROM "names"')
    names = {}
    for row in cursor.fetchall():
        nameid = convert_value(row[0])
        objectname = (row[1] or '').strip() if row[1] is not None else ''
        metricname = (row[2] or '').strip() if row[2] is not None else ''
        names[nameid] = (str(objectname), str(metricname))

    # prefixid -> prefixname
    cursor.execute('SELECT prefixid, prefixname FROM "prefixes" ORDER BY prefixid')
    prefixes = []
    prefixid_to_name = {}
    for row in cursor.fetchall():
        pid, pname = convert_value(row[0]), row[1]
        prefixes.append(pname)
        prefixid_to_name[pid] = pname

    # For each prefix, resolve nameid in values to "objectname.metricname[core]"
    metrics = {}
    for pname in prefixes:
        metrics[pname] = {}

    # Key = objectname.metricname (e.g. thread.time_by_core[0]); metricname often includes [core] in Sniper
    cursor.execute('SELECT prefixid, nameid, core, value FROM "values"')
    for row in cursor.fetchall():
        prefixid, nameid, core, value = convert_value(row[0]), convert_value(row[1]), convert_value(row[2]), convert_value(row[3])
        pname = prefixid_to_name.get(prefixid)
        if pname is None:
            continue
        obj, metric = names.get(nameid, ('', 'unknown'))
        # Key: "object.metric" or just "metric" when object is empty (avoid ".metric" losing first char in some viewers)
        key = f"{obj}.{metric}" if obj else metric
        if not key:
            key = f"nameid_{nameid}"
        metrics[pname][key] = value

    return {
        'prefixes': prefixes,
        'metrics': metrics,
    }


def export_database(sqlite_file, format_type='json', include_raw_tables=False):
    """Export SQLite DB: resolved metrics (default) and optionally raw tables."""
    conn = sqlite3.connect(sqlite_file)
    conn.row_factory = sqlite3.Row
    cursor = conn.cursor()

    result = {
        'database': str(sqlite_file),
    }

    # Human-readable metrics: merge names + values
    if get_all_tables(cursor):
        try:
            resolved = build_resolved_metrics(cursor)
            result['prefixes'] = resolved['prefixes']
            result['metrics'] = resolved['metrics']
        except sqlite3.OperationalError:
            result['metrics'] = {}
            result['prefixes'] = []

    if include_raw_tables:
        result['tables'] = {}
        tables = get_all_tables(cursor)
        for table_name in tables:
            schema = get_table_schema(cursor, table_name)
            columns = [col[1] for col in schema]
            data = export_table_data(cursor, table_name)
            result['tables'][table_name] = {
                'columns': columns,
                'schema': [
                    {'cid': col[0], 'name': col[1], 'type': col[2], 'notnull': bool(col[3]),
                     'default_value': col[4], 'pk': bool(col[5])}
                    for col in schema
                ],
                'data': data,
                'row_count': len(data),
            }

    conn.close()
    return result


def main():
    parser = argparse.ArgumentParser(
        description='Convert Sniper sim.stats.sqlite3 to JSON or YAML format'
    )
    parser.add_argument(
        'sqlite_file',
        type=str,
        help='Path to sim.stats.sqlite3 file'
    )
    parser.add_argument(
        '--format',
        choices=['json', 'yaml'],
        default='json',
        help='Output format (default: json)'
    )
    parser.add_argument(
        '--output',
        type=str,
        help='Output file path (default: <sqlite_file>.<format>)'
    )
    parser.add_argument(
        '--raw',
        action='store_true',
        help='Include raw tables (names, values, etc.) in output in addition to resolved metrics'
    )
    
    args = parser.parse_args()
    
    sqlite_path = Path(args.sqlite_file)
    if not sqlite_path.exists():
        print(f"Error: File not found: {args.sqlite_file}", file=sys.stderr)
        sys.exit(1)
    
    if args.format == 'yaml' and not HAS_YAML:
        print("Error: PyYAML is required for YAML output. Install with: pip install pyyaml", file=sys.stderr)
        sys.exit(1)
    
    # Export database (resolved metrics + optional raw tables)
    try:
        data = export_database(str(sqlite_path), args.format, include_raw_tables=args.raw)
    except sqlite3.Error as e:
        print(f"Error reading SQLite database: {e}", file=sys.stderr)
        sys.exit(1)
    
    # Determine output file
    if args.output:
        output_path = Path(args.output)
    else:
        output_path = sqlite_path.with_suffix(f'.{args.format}')
    
    # Write output
    try:
        with open(output_path, 'w', encoding='utf-8') as f:
            if args.format == 'json':
                json.dump(data, f, indent=2, ensure_ascii=False)
            else:  # yaml
                yaml.dump(data, f, default_flow_style=False, allow_unicode=True, sort_keys=False)
        
        print(f"Successfully converted {sqlite_path} to {output_path}")
        print(f"  Format: {args.format}")
        print(f"  Prefixes: {len(data.get('prefixes', []))}")
        for pname in data.get('prefixes', []):
            n = len(data.get('metrics', {}).get(pname, {}))
            print(f"    - {pname}: {n} metrics")
        if args.raw and 'tables' in data:
            for table_name, table_info in data['tables'].items():
                print(f"  Raw table: {table_name}: {table_info['row_count']} rows")
    except Exception as e:
        print(f"Error writing output file: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == '__main__':
    main()

