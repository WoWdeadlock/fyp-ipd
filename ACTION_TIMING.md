# Action Timing Reference

## Why Actions Take Time

All actions in Godot have realistic timing because:
1. Agents need to move into position
2. Abilities have cast times
3. Animation/cooldown delays

## Measured Action Times

### Tank Actions
- **melee**: 3-7 seconds
  - Tank navigates to boss (2-6s depending on distance)
  - Execute melee attack animation (1.2s)
  - **Recommended wait: 5.0s**

- **taunt**: 0.5s cast + effect
  - **Recommended wait: 1.5s**

- **defensive**: Instant activation
  - **Recommended wait: 1.0s**

### Healer Actions
- **heal**: 1.0s cast time
  - **Recommended wait: 2.0s** (includes safety margin)

- **shield**: 0.8s cast time
  - **Recommended wait: 1.5s**

- **restore**: Similar to heal
  - **Recommended wait: 2.0s**

### Sniper Actions
- **shot**: Positioning + attack
  - Sniper maintains 250 unit range
  - May need to reposition
  - **Recommended wait: 2.0s**

- **cripple**: Similar to shot
  - **Recommended wait: 2.0s**

- **power**: High damage attack
  - **Recommended wait: 2.0s**

## Implications for MCTS

### Training Speed
With these timings, one training episode will take:
- ~50 actions per episode (average)
- ~2-3 seconds per action on average
- **~2-3 minutes per episode**

Full training (50 episodes):
- 50 episodes × 3 minutes = **~2.5 hours minimum**
- With MCTS search time: **~4-6 hours**

### Optimization Options

If training is too slow:

1. **Reduce MCTS iterations**
   - 5000 → 1000 iterations per action
   - Faster but less optimal decisions

2. **Fewer episodes**
   - 50 → 20 episodes
   - Less training but faster

3. **Increase simulation speed in Godot** (future)
   - Modify agent scripts to have instant actions
   - Only for training, not for actual gameplay

4. **Parallel rollouts** (advanced)
   - Run multiple Godot instances
   - Requires significant refactoring

## Current Configuration

[train_mcts.py](train_mcts.py) uses these wait times:
- Melee: 5.0s
- Healer abilities: 2.0s
- Sniper attacks: 2.0s
- Utility (taunt/defensive): 1.5s

These are conservative to ensure actions complete successfully.
