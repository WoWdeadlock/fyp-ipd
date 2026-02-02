"""
Parallel data collection launcher.

Spawns multiple Godot instances, each recording episodes to a separate directory,
then merges all data into a single training dataset.

Usage:
    python parallel_collect.py --godot "path/to/godot" --project "path/to/project" --workers 4 --episodes-per-worker 25

Example:
    python parallel_collect.py --godot "C:/Godot/Godot_v4.5.exe" --project "E:/FYP/IPD/v1" --workers 4 --episodes-per-worker 25 --timescale 3
"""

import argparse
import subprocess
import os
import sys
import time
import json
from pathlib import Path


def get_godot_user_dir():
    """Get the Godot user data directory for the IPD project."""
    return Path(os.environ["APPDATA"]) / "Godot" / "app_userdata" / "IPD"


def launch_worker(godot_path: str, project_path: str, worker_id: int,
                  episodes: int, timescale: float) -> subprocess.Popen:
    """Launch a single Godot worker instance."""
    output_dir = f"user://training_data/worker_{worker_id}"

    cmd = [
        godot_path,
        "--path", project_path,
        "--headless",
        "--",  # Separator for user args
        "--record",
        "--episodes", str(episodes),
        "--output", output_dir,
        "--timescale", str(timescale),
    ]

    print(f"  Worker {worker_id}: {episodes} episodes -> {output_dir}", flush=True)

    # Log stdout/stderr to files for debugging
    log_dir = Path(os.environ["APPDATA"]) / "Godot" / "app_userdata" / "IPD" / "training_data"
    log_dir.mkdir(parents=True, exist_ok=True)
    log_file = open(log_dir / f"worker_{worker_id}.log", "w")
    return subprocess.Popen(cmd, stdout=log_file, stderr=subprocess.STDOUT)


def merge_worker_data(base_dir: Path, num_workers: int, output_dir: Path):
    """Merge data from all workers into a single directory."""
    output_dir.mkdir(parents=True, exist_ok=True)

    all_samples = []
    total_episodes = 0
    total_victories = 0
    total_defeats = 0
    total_time = 0.0

    for worker_id in range(num_workers):
        worker_dir = base_dir / f"worker_{worker_id}"
        if not worker_dir.exists():
            print(f"  WARNING: Worker {worker_id} directory not found: {worker_dir}", flush=True)
            continue

        # Load metadata
        meta_path = worker_dir / "metadata.json"
        if meta_path.exists():
            with open(meta_path) as f:
                meta = json.load(f)
            total_episodes += meta.get("total_episodes", 0)
            total_victories += meta.get("victories", 0)
            total_defeats += meta.get("defeats", 0)
            total_time += meta.get("generation_time_seconds", 0)

        # Load all data files
        for data_file in sorted(worker_dir.glob("data_*.json")):
            with open(data_file) as f:
                samples = json.load(f)
            all_samples.extend(samples)
            print(f"  Worker {worker_id}: loaded {len(samples)} samples from {data_file.name}", flush=True)

    if not all_samples:
        print("ERROR: No samples collected!", flush=True)
        return

    # Write merged data files (5000 samples each)
    samples_per_file = 5000
    file_idx = 0
    for i in range(0, len(all_samples), samples_per_file):
        chunk = all_samples[i:i + samples_per_file]
        out_path = output_dir / f"data_{file_idx:04d}.json"
        with open(out_path, "w") as f:
            json.dump(chunk, f)
        file_idx += 1

    # Write merged metadata
    win_rate = total_victories / total_episodes if total_episodes > 0 else 0
    metadata = {
        "total_episodes": total_episodes,
        "total_samples": len(all_samples),
        "victories": total_victories,
        "defeats": total_defeats,
        "win_rate": win_rate,
        "mcts_iterations": 500,
        "generation_time_seconds": total_time,
        "num_files": file_idx,
        "samples_per_file": samples_per_file,
        "node_feature_dim": 11,
        "edge_feature_dim": 6,
        "num_actions": 10,
        "action_names": ["wait", "melee", "taunt", "defensive",
                         "heal", "shield", "restore",
                         "shot", "cripple", "power"],
        "source": "live_game_parallel"
    }

    with open(output_dir / "metadata.json", "w") as f:
        json.dump(metadata, f, indent=2)

    print(f"\nMerged dataset:", flush=True)
    print(f"  Episodes: {total_episodes}", flush=True)
    print(f"  Samples:  {len(all_samples)}", flush=True)
    print(f"  Win rate: {win_rate:.1%}", flush=True)
    print(f"  Files:    {file_idx}", flush=True)
    print(f"  Output:   {output_dir}", flush=True)


def main():
    parser = argparse.ArgumentParser(description="Parallel MCTS data collection")
    parser.add_argument("--godot", required=True, help="Path to Godot executable")
    parser.add_argument("--project", required=True, help="Path to Godot project directory")
    parser.add_argument("--workers", type=int, default=4, help="Number of parallel workers")
    parser.add_argument("--episodes-per-worker", type=int, default=25, help="Episodes per worker")
    parser.add_argument("--timescale", type=float, default=3.0, help="Game time scale")
    parser.add_argument("--output", type=str, default=None, help="Output directory for merged data (default: user://training_data)")
    args = parser.parse_args()

    base_dir = get_godot_user_dir() / "training_data"
    output_dir = Path(args.output) if args.output else base_dir / "merged"

    total_episodes = args.workers * args.episodes_per_worker
    print(f"Parallel MCTS Data Collection", flush=True)
    print(f"  Workers:    {args.workers}", flush=True)
    print(f"  Episodes:   {args.episodes_per_worker} per worker ({total_episodes} total)", flush=True)
    print(f"  Time scale: {args.timescale}x", flush=True)
    print(f"  Output:     {output_dir}", flush=True)
    print(flush=True)

    # Launch all workers
    print("Launching workers...", flush=True)
    processes = []
    for i in range(args.workers):
        proc = launch_worker(args.godot, args.project, i,
                             args.episodes_per_worker, args.timescale)
        processes.append(proc)

    # Wait for all workers with progress monitoring
    print(f"\nWaiting for {args.workers} workers to finish...", flush=True)
    print(flush=True)
    start_time = time.time()

    # Track log file read positions to tail new lines
    log_positions = {i: 0 for i in range(args.workers)}
    last_summary_time = 0.0

    finished = [False] * args.workers
    while not all(finished):
        for i, proc in enumerate(processes):
            if not finished[i] and proc.poll() is not None:
                finished[i] = True
                elapsed = time.time() - start_time
                print(f"  [Worker {i}] FINISHED (exit code: {proc.returncode}, elapsed: {elapsed:.0f}s)", flush=True)

        # Tail worker log files for new output
        for i in range(args.workers):
            log_path = base_dir / f"worker_{i}.log"
            if not log_path.exists():
                continue
            try:
                with open(log_path, "r") as f:
                    f.seek(log_positions[i])
                    new_content = f.read()
                    log_positions[i] = f.tell()
                if new_content:
                    for line in new_content.splitlines():
                        line = line.strip()
                        if not line:
                            continue
                        # Filter to meaningful lines (episodes, results, errors)
                        lower = line.lower()
                        if any(kw in lower for kw in [
                            "episode", "victory", "defeat", "complete",
                            "sample", "record", "data", "error", "warning",
                            "saved", "win", "lose", "unwinnable", "terminal",
                            "mcts", "running", "start", "finish", "live",
                        ]):
                            print(f"  [w{i}] {line}", flush=True)
            except (OSError, IOError):
                pass

        # Print summary every 10 seconds
        elapsed = time.time() - start_time
        if not all(finished) and elapsed - last_summary_time >= 10:
            last_summary_time = elapsed
            status_parts = []
            total_data_files = 0
            for i in range(args.workers):
                worker_dir = base_dir / f"worker_{i}"
                if worker_dir.exists():
                    data_files = list(worker_dir.glob("data_*.json"))
                    meta = worker_dir / "metadata.json"
                    if meta.exists():
                        status_parts.append(f"w{i}:done")
                    else:
                        status_parts.append(f"w{i}:{len(data_files)}ep")
                    total_data_files += len(data_files)
                else:
                    status_parts.append(f"w{i}:--")

            done_count = sum(finished)
            print(f"  --- [{elapsed:5.0f}s] {done_count}/{args.workers} workers done | episodes: {total_data_files}/{total_episodes} | {' | '.join(status_parts)} ---", flush=True)

        time.sleep(1)

    total_time = time.time() - start_time
    print(f"\nAll workers finished in {total_time:.0f}s", flush=True)

    # Merge data
    print("\nMerging worker data...", flush=True)
    merge_worker_data(base_dir, args.workers, output_dir)

    # Clean up worker directories
    print("\nCleaning up worker directories...", flush=True)
    import shutil
    for i in range(args.workers):
        worker_dir = base_dir / f"worker_{i}"
        if worker_dir.exists():
            shutil.rmtree(worker_dir)
            print(f"  Removed {worker_dir}", flush=True)

    print("\nDone!", flush=True)


if __name__ == "__main__":
    main()
