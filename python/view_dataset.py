"""
Dataset Viewer for GAT Training Data
Analyzes and displays statistics from generated training data.
"""

import json
import os
from pathlib import Path
from collections import Counter

# Godot user data path on Windows
APPDATA = os.environ.get('APPDATA', '')
DATA_DIR = Path(APPDATA) / "Godot" / "app_userdata" / "IPD" / "training_data"

# Action ID to name mapping
ACTION_NAMES = {
    0: "tank_wait",
    1: "tank_melee", 
    2: "tank_taunt",
    3: "tank_defensive",
    4: "healer_wait",
    5: "healer_heal",
    6: "healer_shield",
    7: "healer_restore",
    8: "sniper_wait",
    9: "sniper_shot",
    10: "sniper_cripple",
    11: "sniper_power"
}

def load_all_data(data_dir: Path) -> list:
    """Load all JSON data files."""
    all_samples = []
    
    if not data_dir.exists():
        print(f"Data directory not found: {data_dir}")
        print("\nTry running the data generator in Godot first!")
        return []
    
    json_files = sorted(data_dir.glob("data_*.json"))
    print(f"Found {len(json_files)} data files")
    
    for filepath in json_files:
        with open(filepath, 'r') as f:
            samples = json.load(f)
            all_samples.extend(samples)
            print(f"  Loaded {len(samples)} samples from {filepath.name}")
    
    return all_samples


def analyze_dataset(samples: list):
    """Print dataset statistics."""
    if not samples:
        return
    
    print("\n" + "=" * 60)
    print("DATASET STATISTICS")
    print("=" * 60)
    
    print(f"\nTotal samples: {len(samples)}")
    
    # Action distribution
    action_counts = Counter(s['action_id'] for s in samples)
    print("\n--- Action Distribution ---")
    for action_id, count in sorted(action_counts.items()):
        name = ACTION_NAMES.get(action_id, f"unknown_{action_id}")
        pct = count / len(samples) * 100
        bar = "█" * int(pct / 2)
        print(f"  {name:20s}: {count:5d} ({pct:5.1f}%) {bar}")
    
    # Boss HP distribution
    boss_hp_ratios = [s['boss_hp_ratio'] for s in samples]
    avg_boss_hp = sum(boss_hp_ratios) / len(boss_hp_ratios)
    print(f"\n--- Game State Distribution ---")
    print(f"  Average boss HP ratio: {avg_boss_hp:.2%}")
    
    # Early/mid/late game distribution
    early = sum(1 for r in boss_hp_ratios if r > 0.66)
    mid = sum(1 for r in boss_hp_ratios if 0.33 < r <= 0.66)
    late = sum(1 for r in boss_hp_ratios if r <= 0.33)
    print(f"  Early game (boss >66% HP): {early:5d} ({early/len(samples)*100:.1f}%)")
    print(f"  Mid game (33-66% HP):      {mid:5d} ({mid/len(samples)*100:.1f}%)")
    print(f"  Late game (<33% HP):       {late:5d} ({late/len(samples)*100:.1f}%)")
    
    # Tick distribution
    ticks = [s['tick'] for s in samples]
    print(f"\n  Average game tick: {sum(ticks)/len(ticks):.1f}")
    print(f"  Max tick seen: {max(ticks)}")
    
    print("\n" + "=" * 60)


def show_sample(sample: dict, index: int = 0):
    """Pretty print a single sample."""
    print(f"\n--- Sample #{index} ---")
    print(f"Action: {ACTION_NAMES.get(sample['action_id'], 'unknown')} (id={sample['action_id']})")
    print(f"Tick: {sample['tick']}")
    print(f"Boss HP: {sample['boss_hp_ratio']:.1%}")
    print(f"Legal actions mask: {sample['legal_mask']}")
    
    if 'flat_features' in sample:
        print(f"Features ({len(sample['flat_features'])} dims): {sample['flat_features'][:10]}...")
    
    if 'graph' in sample:
        print(f"Graph nodes: {len(sample['graph'].get('nodes', []))}")
        print(f"Graph edges: {len(sample['graph'].get('edges', []))}")


def main():
    print("=" * 60)
    print("GAT TRAINING DATA VIEWER")
    print("=" * 60)
    print(f"\nLooking for data in: {DATA_DIR}")
    
    samples = load_all_data(DATA_DIR)
    
    if samples:
        analyze_dataset(samples)
        
        # Show a few sample entries
        print("\n--- Sample Entries ---")
        for i in [0, len(samples)//2, len(samples)-1]:
            if i < len(samples):
                show_sample(samples[i], i)
        
        # Check for metadata
        metadata_path = DATA_DIR / "metadata.json"
        if metadata_path.exists():
            with open(metadata_path) as f:
                meta = json.load(f)
            print("\n--- Generation Metadata ---")
            print(f"  Episodes: {meta.get('total_episodes')}")
            print(f"  Win rate: {meta.get('win_rate', 0):.1%}")
            print(f"  MCTS iterations: {meta.get('mcts_iterations')}")
            print(f"  Generation time: {meta.get('generation_time_seconds', 0):.1f}s")


if __name__ == "__main__":
    main()
