#!/usr/bin/env python3
"""Bidirectional sync between tasks.md and beads (bd) issues.

Usage:
  sdd-beads-sync.py <tasks-file>            # Forward sync (tasks -> bd)
  sdd-beads-sync.py <tasks-file> --reverse  # Reverse sync (bd -> tasks.md)
  sdd-beads-sync.py <tasks-file> --status   # Show sync status
  sdd-beads-sync.py <tasks-file> --dry-run  # Preview without creating

Forward sync: Parses tasks.md, creates bd issues with dependencies and hierarchy.
Reverse sync: Updates tasks.md checkboxes from bd issue status.
"""

import argparse
import json
import re
import shutil
import subprocess
import sys
from pathlib import Path


# --- Patterns ---

RE_PHASE = re.compile(r'^## Phase (\d+):\s*(.*)')
RE_TASK = re.compile(r'^- \[([ Xx])\] (T\d+)\s+(\(bd-[a-zA-Z0-9_-]+\)\s*)?(.*)')
RE_BD_MARKER = re.compile(r'\(bd-([a-zA-Z0-9_-]+)\)')
RE_PARALLEL = re.compile(r'\[P\]')
RE_USER_STORY = re.compile(r'\[(US\d+)\]')
RE_DEPS_HEADER = re.compile(r'^## Dependenc', re.IGNORECASE)
RE_PHASE_DEP = re.compile(r'(?:depends on|after)\s+phases?\s+([\d,\s-]+)', re.IGNORECASE)
RE_PHASE_SOURCE = re.compile(r'\*\*.*Phase\s+(\d+)')


# --- BD CLI helpers ---

def run_bd(*args, capture=True, check=True):
    """Run a bd CLI command and return stdout."""
    cmd = ['bd'] + list(args)
    try:
        result = subprocess.run(
            cmd, capture_output=capture, text=True, check=check
        )
        return result.stdout.strip() if capture else ''
    except subprocess.CalledProcessError as e:
        if check:
            raise
        return ''
    except FileNotFoundError:
        print("ERROR: beads CLI (bd) is not installed.", file=sys.stderr)
        print("Install beads: https://github.com/beads-project/beads", file=sys.stderr)
        sys.exit(1)


def check_bd():
    """Verify bd CLI is available."""
    if not shutil.which('bd'):
        print("ERROR: beads CLI (bd) is not installed.", file=sys.stderr)
        print("Install beads: https://github.com/beads-project/beads", file=sys.stderr)
        sys.exit(1)


def ensure_bd_init(dry_run):
    """Initialize bd database if not present."""
    try:
        run_bd('list', '--json')
    except (subprocess.CalledProcessError, Exception):
        if dry_run:
            print("[dry-run] Would run: bd init")
        else:
            run_bd('init')
            print("Initialized beads database.")


def find_by_spec_id(spec_id):
    """Look up a bd issue by spec-id, return its ID or None."""
    try:
        output = run_bd('list', '--json', check=False)
        if not output:
            return None
        issues = json.loads(output)
        for issue in issues:
            if issue.get('spec_id') == spec_id:
                return issue['id']
    except (json.JSONDecodeError, KeyError):
        pass
    return None


def bd_create(title, dry_run, **kwargs):
    """Create a bd issue and return its ID."""
    args = [title]
    for key, value in kwargs.items():
        if value is not None:
            flag = f'--{key.replace("_", "-")}'
            args.extend([flag, str(value)])
    args.append('--silent')

    if dry_run:
        print(f'[dry-run] bd create "{title}" {" ".join(args[1:])}')
        return 'dry-run-id'
    return run_bd('create', *args)


def bd_close(issue_id, dry_run):
    """Close a bd issue."""
    if dry_run:
        print(f"[dry-run] bd close {issue_id}")
    else:
        run_bd('close', issue_id, check=False)


def bd_dep_add(issue_id, blocked_by, dry_run):
    """Add a dependency between two issues."""
    if dry_run:
        print(f"[dry-run] bd dep add {issue_id} --blocked-by {blocked_by}")
    else:
        run_bd('dep', 'add', issue_id, '--blocked-by', blocked_by, check=False)


def bd_show_json(issue_id):
    """Get issue details as dict.

    bd show returns a JSON array (even for a single issue) or an error object
    like {"error": "..."}. This function extracts the first element from the
    array, or returns an empty dict on error.
    """
    try:
        output = run_bd('show', issue_id, '--json', check=False)
        if output:
            data = json.loads(output)
            if isinstance(data, list) and data:
                return data[0]
            if isinstance(data, dict) and 'error' not in data:
                return data
    except json.JSONDecodeError:
        pass
    return {}


def bd_list_json():
    """Get all issues as list of dicts.

    Returns an empty list if bd returns an error object like {"error": "..."}.
    """
    try:
        output = run_bd('list', '--json', check=False)
        if output:
            data = json.loads(output)
            if isinstance(data, list):
                return data
    except json.JSONDecodeError:
        pass
    return []


# --- Forward Sync ---

def ensure_db_fresh():
    """Restore database from backup files if available.

    After a fresh clone or if the Dolt database was lost, ``bd backup restore``
    rebuilds the database from the JSONL backup files in ``.beads/backup/``.
    This is a no-op if the database is already up to date.
    """
    run_bd('backup', 'restore', check=False)


def do_forward_sync(tasks_file, dry_run):
    check_bd()
    ensure_bd_init(dry_run)
    ensure_db_fresh()

    lines = tasks_file.read_text().splitlines()

    phase_ids = {}       # phase_num (str) -> bd_id
    task_bd_ids = {}     # task_id (e.g. "T001") -> bd_id
    phase_dep_rules = [] # list of (target_phase, dep_phase) tuples

    current_phase_num = None
    phase_id = None
    prev_task_id = None
    in_deps_section = False

    tasks_created = 0
    tasks_skipped = 0
    phases_created = 0
    deps_added = 0

    for line in lines:
        # Detect dependencies section
        if RE_DEPS_HEADER.search(line):
            in_deps_section = True
            current_phase_num = None
            continue

        # Phase header
        m = RE_PHASE.match(line)
        if m:
            in_deps_section = False
            current_phase_num = m.group(1)
            current_phase_title = m.group(2).strip()
            prev_task_id = None

            existing = find_by_spec_id(f"phase-{current_phase_num}")
            if existing:
                phase_id = existing
                phase_ids[current_phase_num] = phase_id
                print(f"Phase {current_phase_num}: already exists ({phase_id})")
            else:
                title = f"Phase {current_phase_num}: {current_phase_title}"
                phase_id = bd_create(
                    title, dry_run,
                    type='epic',
                    labels=f'phase:{current_phase_num}',
                    spec_id=f'phase-{current_phase_num}',
                )
                phase_ids[current_phase_num] = phase_id
                phases_created += 1
                print(f"Phase {current_phase_num}: created ({phase_id})")
            continue

        # Parse inter-phase dependencies
        if in_deps_section:
            if RE_PHASE_DEP.search(line):
                src_m = RE_PHASE_SOURCE.search(line)
                dep_m = RE_PHASE_DEP.search(line)
                if src_m and dep_m:
                    src_phase = src_m.group(1)
                    dep_nums = re.findall(r'\d+', dep_m.group(1))
                    for dp in dep_nums:
                        if dp != src_phase:
                            phase_dep_rules.append((src_phase, dp))
            continue

        # Task line
        m = RE_TASK.match(line)
        if not m:
            continue

        checkbox = m.group(1)
        task_id = m.group(2)
        bd_marker_group = m.group(3)
        desc = m.group(4)

        is_parallel = bool(RE_PARALLEL.search(desc))

        # Strip markers from description for the issue title
        clean_desc = RE_PARALLEL.sub('', desc)
        clean_desc = RE_USER_STORY.sub('', clean_desc)
        clean_desc = RE_BD_MARKER.sub('', clean_desc).strip()

        # Check for existing bd marker in line
        existing_marker = None
        if bd_marker_group:
            marker_m = RE_BD_MARKER.search(bd_marker_group)
            if marker_m:
                existing_marker = f"bd-{marker_m.group(1)}"

        # Skip if already synced
        if existing_marker:
            task_bd_ids[task_id] = existing_marker
            tasks_skipped += 1
            prev_task_id = task_id
            print(f"  {task_id}: already synced ({existing_marker})")
            continue

        # Check by spec-id
        bd_id = find_by_spec_id(task_id)
        if bd_id:
            task_bd_ids[task_id] = bd_id
            tasks_skipped += 1
            prev_task_id = task_id
            print(f"  {task_id}: found by spec-id ({bd_id})")
            continue

        # Build labels
        labels_parts = [f"phase:{current_phase_num or 0}"]
        us_m = RE_USER_STORY.search(desc)
        if us_m:
            labels_parts.append(us_m.group(1))
        if is_parallel:
            labels_parts.append('parallel')
        labels = ','.join(labels_parts)

        # Split into crisp title and detailed description.
        # Beads titles have length restrictions, so keep the title short
        # and put the full description into a comment.
        title_text = clean_desc
        detail_text = None
        # Truncate title at first colon or period that separates a summary
        # from detail, or hard-cap at 80 chars.
        max_title_len = 80
        for sep in (':', '. '):
            idx = clean_desc.find(sep)
            if 0 < idx < max_title_len:
                title_text = clean_desc[:idx].strip()
                detail_text = clean_desc[idx + len(sep):].strip()
                break
        if len(title_text) > max_title_len:
            title_text = title_text[:max_title_len].rsplit(' ', 1)[0] + '...'
            detail_text = clean_desc

        # Create issue
        create_kwargs = {
            'spec_id': task_id,
            'labels': labels,
        }
        if phase_id:
            create_kwargs['parent'] = phase_id

        bd_id = bd_create(f"{task_id}: {title_text}", dry_run, **create_kwargs)

        # Add full description as a comment if it was truncated
        if detail_text and not dry_run:
            run_bd('comments', 'add', bd_id, detail_text, check=False)
        elif detail_text and dry_run:
            print(f'  [dry-run] bd comments add {bd_id} "{detail_text[:60]}..."')
        task_bd_ids[task_id] = bd_id
        tasks_created += 1

        # Close if already checked
        if checkbox in ('X', 'x'):
            bd_close(bd_id, dry_run)

        # Sequential dependency (non-parallel tasks within same phase)
        if not is_parallel and prev_task_id and prev_task_id in task_bd_ids:
            bd_dep_add(bd_id, task_bd_ids[prev_task_id], dry_run)
            deps_added += 1

        prev_task_id = task_id
        print(f"  {task_id}: created ({bd_id})")

    # Apply inter-phase dependencies
    for target_phase, dep_phase in phase_dep_rules:
        target_pid = phase_ids.get(target_phase)
        dep_pid = phase_ids.get(dep_phase)
        if target_pid and dep_pid:
            bd_dep_add(target_pid, dep_pid, dry_run)
            deps_added += 1
            if dry_run:
                print(f"  Phase {target_phase} -> Phase {dep_phase}")

    # Update tasks.md with (bd-XXXX) markers
    if not dry_run:
        updated_lines = []
        for line in lines:
            m = RE_TASK.match(line)
            if m and not m.group(3):
                tid = m.group(2)
                bid = task_bd_ids.get(tid)
                if bid:
                    line = line.replace(tid, f"{tid} ({bid})", 1)
            updated_lines.append(line)
        tasks_file.write_text('\n'.join(updated_lines) + '\n')

    # Final backup to persist state for git
    if not dry_run:
        run_bd('backup', check=False)

    print()
    print("Forward sync complete:")
    print(f"  Phases: {phases_created} created")
    print(f"  Tasks: {tasks_created} created, {tasks_skipped} skipped (already exist)")
    print(f"  Dependencies: {deps_added} added")


# --- Reverse Sync ---

def do_reverse_sync(tasks_file, dry_run):
    check_bd()
    ensure_db_fresh()

    lines = tasks_file.read_text().splitlines()
    updated_lines = []
    updated_count = 0

    for line in lines:
        m = RE_TASK.match(line)
        if m and m.group(3):
            marker_m = RE_BD_MARKER.search(m.group(3))
            if marker_m:
                bd_id = f"bd-{marker_m.group(1)}"
                info = bd_show_json(bd_id)
                status = info.get('status', 'unknown')
                checkbox = m.group(1)

                if status == 'closed' and checkbox not in ('X', 'x'):
                    line = re.sub(r'^- \[ \]', '- [X]', line)
                    updated_count += 1
                elif status == 'open' and checkbox in ('X', 'x'):
                    line = re.sub(r'^- \[[Xx]\]', '- [ ]', line)
                    updated_count += 1

        updated_lines.append(line)

    # Append discovered work from bd
    discovered_count = 0
    all_issues = bd_list_json()
    discovered = [
        i for i in all_issues
        if 'discovered' in (i.get('labels') or [])
        and not i.get('spec_id')
    ]

    if discovered:
        updated_lines.append('')
        updated_lines.append('## Discovered Work')
        updated_lines.append('')
        for issue in discovered:
            status = issue.get('status', 'open')
            check = 'X' if status == 'closed' else ' '
            title = issue.get('title', '')
            if title.startswith('DISCOVERED: '):
                title = title[len('DISCOVERED: '):]
            bid = issue['id']
            updated_lines.append(f"- [{check}] ({bid}) {title}")
            discovered_count += 1

    if not dry_run:
        tasks_file.write_text('\n'.join(updated_lines) + '\n')

    print("Reverse sync complete:")
    print(f"  Checkboxes updated: {updated_count}")
    print(f"  Discovered work added: {discovered_count}")


# --- Status ---

def do_status(tasks_file):
    check_bd()
    ensure_db_fresh()

    lines = tasks_file.read_text().splitlines()
    total = 0
    checked = 0
    synced = 0
    unsynced = 0

    for line in lines:
        m = RE_TASK.match(line)
        if m:
            total += 1
            if m.group(1) in ('X', 'x'):
                checked += 1
            if m.group(3):
                synced += 1
            else:
                unsynced += 1

    print(f"Beads sync status for: {tasks_file}")
    print(f"  Total tasks: {total}")
    print(f"  Completed:   {checked}")
    print(f"  Synced (bd): {synced}")
    print(f"  Unsynced:    {unsynced}")

    # BD database stats
    all_issues = bd_list_json()
    bd_open = sum(1 for i in all_issues if i.get('status') == 'open')
    bd_closed = sum(1 for i in all_issues if i.get('status') == 'closed')
    print()
    print("Beads database:")
    print(f"  Total issues: {len(all_issues)}")
    print(f"  Open:         {bd_open}")
    print(f"  Closed:       {bd_closed}")


# --- Main ---

def main():
    parser = argparse.ArgumentParser(
        description='Bidirectional sync between tasks.md and beads (bd) issues'
    )
    parser.add_argument('tasks_file', type=Path, help='Path to tasks.md')
    parser.add_argument('--reverse', action='store_true',
                        help='Reverse sync (bd -> tasks.md)')
    parser.add_argument('--status', action='store_true',
                        help='Show sync status')
    parser.add_argument('--dry-run', action='store_true',
                        help='Preview without creating')

    args = parser.parse_args()

    if not args.tasks_file.is_file():
        print(f"ERROR: tasks file not found: {args.tasks_file}", file=sys.stderr)
        sys.exit(1)

    if args.status:
        do_status(args.tasks_file)
    elif args.reverse:
        do_reverse_sync(args.tasks_file, args.dry_run)
    else:
        do_forward_sync(args.tasks_file, args.dry_run)


if __name__ == '__main__':
    main()
