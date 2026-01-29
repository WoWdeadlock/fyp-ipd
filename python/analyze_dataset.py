"""
Dataset Analysis - Correlations & Patterns from MCTS Training Data
Finds what strategies/patterns the MCTS discovered that work well.
"""

import json
import os
from pathlib import Path
from collections import Counter, defaultdict
import statistics

APPDATA = os.environ.get('APPDATA', '')
DATA_DIR = Path(APPDATA) / "Godot" / "app_userdata" / "IPD" / "training_data"

# Matches GraphExporter.ACTION_TO_ID in graph_exporter.gd
ACTION_NAMES = {
    0: "wait",       1: "melee",    2: "taunt",    3: "defensive",
    4: "heal",       5: "shield",   6: "restore",
    7: "shot",       8: "cripple",  9: "power"
}

AGENT_NAMES = {0: "tank", 1: "healer", 2: "sniper"}


def get_agent(s):
    """Get agent name from sample, using agent_idx field."""
    return AGENT_NAMES.get(s.get('agent_idx', -1), "unknown")


def load_all_data(data_dir: Path) -> list:
    all_samples = []
    if not data_dir.exists():
        print(f"Data directory not found: {data_dir}")
        return []
    for filepath in sorted(data_dir.glob("data_*.json")):
        with open(filepath, 'r') as f:
            all_samples.extend(json.load(f))
    print(f"Loaded {len(all_samples)} samples")
    return all_samples


def load_metadata(data_dir: Path) -> dict:
    meta_path = data_dir / "metadata.json"
    if meta_path.exists():
        with open(meta_path) as f:
            return json.load(f)
    return {}


def phase_label(boss_hp_ratio: float) -> str:
    if boss_hp_ratio > 0.66:
        return "early"
    elif boss_hp_ratio > 0.33:
        return "mid"
    else:
        return "late"


def analyze(samples: list):
    if not samples:
        print("No samples to analyze.")
        return

    n = len(samples)
    sep = "=" * 65

    # ── 1. Overall action distribution ──
    print(f"\n{sep}")
    print("1. OVERALL ACTION DISTRIBUTION")
    print(sep)
    action_counts = Counter(s['action_id'] for s in samples)
    for aid, count in sorted(action_counts.items(), key=lambda x: -x[1]):
        pct = count / n * 100
        bar = "█" * int(pct / 2)
        print(f"  {ACTION_NAMES[aid]:20s}: {count:6d} ({pct:5.1f}%) {bar}")

    # ── 2. Action distribution by game phase ──
    print(f"\n{sep}")
    print("2. ACTION PREFERENCES BY GAME PHASE")
    print(sep)
    phase_actions = defaultdict(Counter)
    for s in samples:
        phase = phase_label(s['boss_hp_ratio'])
        phase_actions[phase][s['action_id']] += 1

    for phase in ["early", "mid", "late"]:
        total = sum(phase_actions[phase].values())
        if total == 0:
            continue
        print(f"\n  [{phase.upper()} GAME] ({total} samples)")
        for aid, count in sorted(phase_actions[phase].items(), key=lambda x: -x[1])[:6]:
            pct = count / total * 100
            print(f"    {ACTION_NAMES[aid]:20s}: {pct:5.1f}%")

    # ── 3. Per-agent action preferences ──
    print(f"\n{sep}")
    print("3. PER-AGENT ACTION PREFERENCES")
    print(sep)
    agent_actions = defaultdict(Counter)
    for s in samples:
        agent = get_agent(s)
        agent_actions[agent][s['action_id']] += 1

    for agent in ["tank", "healer", "sniper"]:
        total = sum(agent_actions[agent].values())
        if total == 0:
            continue
        print(f"\n  [{agent.upper()}] ({total} decisions)")
        for aid, count in sorted(agent_actions[agent].items(), key=lambda x: -x[1]):
            pct = count / total * 100
            bar = "█" * int(pct / 2)
            print(f"    {ACTION_NAMES[aid]:20s}: {pct:5.1f}% {bar}")

    # ── 4. Conditional patterns: what does healer do when tank is low? ──
    print(f"\n{sep}")
    print("4. HEALER BEHAVIOR vs TANK HP")
    print(sep)
    if 'flat_features' in samples[0] or 'node_features' in samples[0]:
        healer_samples = [s for s in samples if get_agent(s) == "healer"]
        # Try to get tank HP from node_features (node 0) or flat_features
        tank_low_actions = Counter()
        tank_high_actions = Counter()
        for s in healer_samples:
            tank_hp = None
            if 'node_features' in s:
                # node 0 = tank, feature 0 is typically hp_ratio
                tank_hp = s['node_features'][0][0] if len(s['node_features']) > 0 else None
            elif 'flat_features' in s:
                # First feature is typically tank hp ratio
                tank_hp = s['flat_features'][0] if len(s['flat_features']) > 0 else None

            if tank_hp is not None:
                if tank_hp < 0.5:
                    tank_low_actions[s['action_id']] += 1
                else:
                    tank_high_actions[s['action_id']] += 1

        if tank_low_actions:
            total_low = sum(tank_low_actions.values())
            print(f"\n  When Tank HP < 50% ({total_low} samples):")
            for aid, count in sorted(tank_low_actions.items(), key=lambda x: -x[1]):
                print(f"    {ACTION_NAMES[aid]:20s}: {count/total_low*100:5.1f}%")

        if tank_high_actions:
            total_high = sum(tank_high_actions.values())
            print(f"\n  When Tank HP >= 50% ({total_high} samples):")
            for aid, count in sorted(tank_high_actions.items(), key=lambda x: -x[1]):
                print(f"    {ACTION_NAMES[aid]:20s}: {count/total_high*100:5.1f}%")
    else:
        print("  (no feature data available for conditional analysis)")

    # ── 5. Sniper ability usage by game phase ──
    print(f"\n{sep}")
    print("5. SNIPER ABILITY USAGE BY PHASE")
    print(sep)
    sniper_phase = defaultdict(Counter)
    for s in samples:
        if get_agent(s) == "sniper":
            phase = phase_label(s['boss_hp_ratio'])
            sniper_phase[phase][s['action_id']] += 1

    for phase in ["early", "mid", "late"]:
        total = sum(sniper_phase[phase].values())
        if total == 0:
            continue
        print(f"\n  [{phase.upper()}] ({total} samples)")
        for aid, count in sorted(sniper_phase[phase].items(), key=lambda x: -x[1]):
            pct = count / total * 100
            print(f"    {ACTION_NAMES[aid]:20s}: {pct:5.1f}%")

    # ── 6. Tank defensive/taunt timing ──
    print(f"\n{sep}")
    print("6. TANK TAUNT & DEFENSIVE TIMING")
    print(sep)
    tank_samples = [s for s in samples if get_agent(s) == "tank"]
    taunt_boss_hp = [s['boss_hp_ratio'] for s in tank_samples if s['action_id'] == 2]
    def_boss_hp = [s['boss_hp_ratio'] for s in tank_samples if s['action_id'] == 3]
    melee_boss_hp = [s['boss_hp_ratio'] for s in tank_samples if s['action_id'] == 1]

    for name, vals in [("taunt", taunt_boss_hp), ("defensive", def_boss_hp), ("melee", melee_boss_hp)]:
        if vals:
            print(f"\n  {name}: used {len(vals)} times")
            print(f"    avg boss HP when used: {statistics.mean(vals):.1%}")
            print(f"    min/max boss HP:       {min(vals):.1%} / {max(vals):.1%}")

    # ── 7. "Wait" action frequency (potential issue flag) ──
    print(f"\n{sep}")
    print("7. WAIT ACTION FREQUENCY (efficiency check)")
    print(sep)
    wait_ids = [0, 4, 8]
    wait_count = sum(action_counts.get(wid, 0) for wid in wait_ids)
    print(f"  Total waits: {wait_count} / {n} ({wait_count/n*100:.1f}%)")
    for wid in wait_ids:
        c = action_counts.get(wid, 0)
        print(f"    {ACTION_NAMES[wid]:20s}: {c:6d} ({c/n*100:.1f}%)")
    if wait_count / n > 0.3:
        print("  ⚠ High wait ratio - agents may be idle too often")

    # ── 8. Legal mask utilization ──
    print(f"\n{sep}")
    print("8. LEGAL MASK STATS")
    print(sep)
    legal_counts = [sum(s['legal_mask']) for s in samples]
    print(f"  Avg legal actions per decision: {statistics.mean(legal_counts):.1f}")
    print(f"  Min / Max: {min(legal_counts)} / {max(legal_counts)}")

    # ── 9. Co-occurrence: actions chosen in sequence (by tick) ──
    print(f"\n{sep}")
    print("9. ACTION SEQUENCES (consecutive decisions)")
    print(sep)
    pair_counts = Counter()
    for i in range(1, len(samples)):
        if samples[i]['tick'] == samples[i-1]['tick'] or abs(samples[i]['tick'] - samples[i-1]['tick']) <= 2:
            pair = (ACTION_NAMES[samples[i-1]['action_id']], ACTION_NAMES[samples[i]['action_id']])
            pair_counts[pair] += 1

    print("  Top 10 action pairs (within ~2 ticks):")
    for (a1, a2), count in pair_counts.most_common(10):
        print(f"    {a1:20s} → {a2:20s}: {count}")

    # ── 10. Summary insights ──
    print(f"\n{sep}")
    print("10. KEY INSIGHTS SUMMARY")
    print(sep)

    # Most used ability per agent
    for agent in ["tank", "healer", "sniper"]:
        if agent_actions[agent]:
            top_aid = agent_actions[agent].most_common(1)[0][0]
            top_pct = agent_actions[agent][top_aid] / sum(agent_actions[agent].values()) * 100
            print(f"  {agent.upper():8s} favorite: {ACTION_NAMES[top_aid]:20s} ({top_pct:.0f}%)")

    # Phase shift detection
    agent_phase_counter = defaultdict(lambda: defaultdict(Counter))
    for s in samples:
        phase = phase_label(s['boss_hp_ratio'])
        agent_phase_counter[get_agent(s)][phase][s['action_id']] += 1

    for agent in ["tank", "healer", "sniper"]:
        early_acts = agent_phase_counter[agent].get("early", {})
        late_acts = agent_phase_counter[agent].get("late", {})
        early_top = max(early_acts, key=early_acts.get) if early_acts else None
        late_top = max(late_acts, key=late_acts.get) if late_acts else None
        if early_top and late_top and early_top != late_top:
            print(f"  {agent.upper():8s} shifts: {ACTION_NAMES[early_top]} (early) → {ACTION_NAMES[late_top]} (late)")


def main():
    print("MCTS DATASET ANALYSIS - Patterns & Correlations")
    print(f"Data dir: {DATA_DIR}\n")

    meta = load_metadata(DATA_DIR)
    if meta:
        print(f"Episodes: {meta.get('total_episodes', '?')} | "
              f"Win rate: {meta.get('win_rate', 0):.1%} | "
              f"MCTS iters: {meta.get('mcts_iterations', '?')}")

    samples = load_all_data(DATA_DIR)
    analyze(samples)


if __name__ == "__main__":
    main()
