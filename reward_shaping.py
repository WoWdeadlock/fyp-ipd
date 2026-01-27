"""
Generalizable reward shaping system for MCTS combat learning.

This module provides role-based, event-driven rewards that enable
strategic learning without hardcoded scenario rules.
"""

from typing import Dict, Tuple, Optional

# Action costs (stamina required)
ACTION_COSTS = {
    ("tank", "melee"): 20,
    ("tank", "taunt"): 15,
    ("tank", "defensive"): 10,
    ("healer", "heal"): 40,
    ("healer", "shield"): 30,
    ("healer", "restore"): 50,
    ("sniper", "shot"): 25,
    ("sniper", "cripple"): 40,
    ("sniper", "power"): 60,
}

# Maximum health and stamina for each agent
MAX_HP = {"tank": 150, "healer": 70, "sniper": 80, "boss": 500}
MAX_STAMINA = {"tank": 80, "healer": 150, "sniper": 120, "boss": 300}

# Role importance weights (higher = more critical to protect)
ROLE_WEIGHTS = {"healer": 3.0, "sniper": 2.0, "tank": 1.5}


class StateTransition:
    """Represents a state transition with derived metric computation."""

    def __init__(self, prev_state: Dict, action: Tuple, next_state: Dict):
        self.prev = prev_state
        self.action = action
        self.next = next_state
        self.agent, self.ability, self.target = action

    def boss_damage_dealt(self) -> int:
        """Calculate damage dealt to boss."""
        prev_hp = self.prev.get('boss', {}).get('hp', 0)
        next_hp = self.next.get('boss', {}).get('hp', 0)
        return max(0, prev_hp - next_hp)

    def agent_damage_taken(self, agent_name: str) -> int:
        """Calculate damage taken by specific agent."""
        prev_hp = self.prev.get(agent_name, {}).get('hp', 0)
        next_hp = self.next.get(agent_name, {}).get('hp', 0)
        return max(0, prev_hp - next_hp)

    def hp_restored(self, agent_name: str) -> int:
        """Calculate HP restored to specific agent."""
        prev_hp = self.prev.get(agent_name, {}).get('hp', 0)
        next_hp = self.next.get(agent_name, {}).get('hp', 0)
        return max(0, next_hp - prev_hp)

    def stamina_efficiency(self) -> float:
        """Calculate damage dealt per stamina spent."""
        damage = self.boss_damage_dealt()
        cost = ACTION_COSTS.get(self.action, 1)
        if cost == 0:
            return 0.0
        return damage / float(cost)

    def vulnerability_score(self, agent_name: str) -> float:
        """
        Calculate how vulnerable an agent is (0-3 scale).
        Higher score = more vulnerable (low HP + important role).
        """
        next_hp = self.next.get(agent_name, {}).get('hp', 0)
        max_hp = MAX_HP.get(agent_name, 100)

        # Avoid division by zero
        if max_hp == 0:
            return 0.0

        hp_ratio = next_hp / float(max_hp)
        role_weight = ROLE_WEIGHTS.get(agent_name, 1.0)

        # vulnerability increases as HP decreases
        return (1.0 - hp_ratio) * role_weight

    def threat_reduction(self) -> float:
        """
        Calculate reward for reducing threat to vulnerable allies.
        High reward if boss switches from vulnerable ally to tank.
        """
        prev_target = self.prev.get('boss', {}).get('current_target_name', '')
        next_target = self.next.get('boss', {}).get('current_target_name', '')

        # If boss switched from healer/sniper to tank, that's great!
        if prev_target in ['healer', 'sniper'] and next_target == 'tank':
            # Reward is proportional to how vulnerable the previous target was
            vulnerability = self.vulnerability_score(prev_target)
            return vulnerability * 100.0  # 0-300 range

        return 0.0

    def damage_prevented(self) -> float:
        """
        Estimate damage prevented by shields/defensive stance.
        This is approximate since we don't know what would have happened.
        """
        if self.ability in ['shield', 'defensive']:
            # Estimate average boss damage
            avg_boss_damage = 20.0
            return avg_boss_damage * 0.5  # Assume 50% damage reduction benefit
        return 0.0

    def healing_efficiency(self) -> float:
        """
        Calculate healing efficiency based on target vulnerability.
        More reward for healing critical allies.
        """
        if self.ability != 'heal':
            return 0.0

        target_agent = self.target if self.target else ""
        if not target_agent or target_agent not in ['tank', 'healer', 'sniper']:
            return 0.0

        hp_restored = self.hp_restored(target_agent)
        vulnerability = self.vulnerability_score(target_agent)

        # High vulnerability + healing = high value
        return vulnerability * hp_restored * 0.5  # 0-120 range typically

    def stamina_restored(self) -> float:
        """Calculate stamina restoration value."""
        if self.ability != 'restore':
            return 0.0

        target_agent = self.target if self.target else ""
        if not target_agent:
            return 0.0

        prev_stam = self.prev.get(target_agent, {}).get('stamina', 0)
        next_stam = self.next.get(target_agent, {}).get('stamina', 0)
        restored = max(0, next_stam - prev_stam)

        # Value based on how low stamina was (low stamina = high value restore)
        max_stam = MAX_STAMINA.get(target_agent, 100)
        stam_ratio = prev_stam / float(max_stam) if max_stam > 0 else 1.0
        urgency = 1.0 - stam_ratio  # Higher when stamina was low

        return urgency * restored * 0.3  # 0-60 range


def compute_action_reward(transition: StateTransition) -> float:
    """
    Compute immediate rewards for action effectiveness.
    Rewards direct outcomes like damage, healing, protection.
    """
    reward = 0.0

    # 1. Damage dealing rewards
    damage = transition.boss_damage_dealt()
    if damage > 0:
        reward += damage * 0.5  # Raw damage reward
        efficiency = transition.stamina_efficiency()
        reward += efficiency * 2.0  # Efficiency bonus (damage per stamina)

    # 2. Protection effectiveness
    threat_reduced = transition.threat_reduction()
    reward += threat_reduced  # Big reward for protecting vulnerable allies

    # 3. Healing efficiency
    healing_value = transition.healing_efficiency()
    reward += healing_value

    # 4. Stamina restoration
    stamina_value = transition.stamina_restored()
    reward += stamina_value

    # 5. Damage prevention (shields, defensive)
    prevented = transition.damage_prevented()
    reward += prevented * 0.8

    # 6. Penalties for letting agents take damage (role-weighted)
    for agent in ['healer', 'sniper', 'tank']:
        damage_taken = transition.agent_damage_taken(agent)
        if damage_taken > 0:
            vulnerability = transition.vulnerability_score(agent)
            # More penalty if vulnerable agent takes damage
            reward -= damage_taken * vulnerability * 0.5

    return reward


def compute_team_safety(state: Dict) -> float:
    """
    Calculate overall team safety score (0-1).
    Higher = safer team state.
    """
    if not state:
        return 0.0

    # Role-weighted HP ratios
    tank_hp = state.get('tank', {}).get('hp', 0)
    healer_hp = state.get('healer', {}).get('hp', 0)
    sniper_hp = state.get('sniper', {}).get('hp', 0)

    tank_safety = (tank_hp / float(MAX_HP['tank'])) * 1.0
    healer_safety = (healer_hp / float(MAX_HP['healer'])) * 2.0
    sniper_safety = (sniper_hp / float(MAX_HP['sniper'])) * 1.5

    # Bonus if boss targets tank (good positioning)
    target_bonus = 0.5 if state.get('boss', {}).get('current_target_name') == 'tank' else 0.0

    # Average with role weights
    total = tank_safety + healer_safety + sniper_safety + target_bonus
    return total / 5.0  # Normalize to 0-1


def compute_resource_efficiency(transition: StateTransition) -> float:
    """
    Calculate resource management score.
    Penalizes letting stamina drop too low.
    """
    efficiency = 0.0

    for agent in ['tank', 'healer', 'sniper']:
        next_stamina = transition.next.get(agent, {}).get('stamina', 0)
        max_stamina = MAX_STAMINA.get(agent, 100)

        stamina_ratio = next_stamina / float(max_stamina) if max_stamina > 0 else 0.0

        # Penalty if stamina drops below 30%
        if stamina_ratio < 0.3:
            efficiency -= 5.0

    return efficiency


def compute_state_improvement_reward(transition: StateTransition) -> float:
    """
    Compute rewards for improving overall team state.
    Focuses on strategic positioning and resource management.
    """
    reward = 0.0

    # 1. Team safety improvement
    prev_safety = compute_team_safety(transition.prev)
    next_safety = compute_team_safety(transition.next)
    safety_delta = next_safety - prev_safety
    reward += safety_delta * 20.0  # Significant reward for improving safety

    # 2. Resource management
    resource_delta = compute_resource_efficiency(transition)
    reward += resource_delta * 5.0

    return reward


def compute_episode_reward(steps: int, outcome: str) -> float:
    """
    Compute terminal reward for episode outcome.
    Victory gives bonus, faster victory gives more bonus.
    """
    if outcome == 'victory':
        # Base victory reward + speed bonus
        time_bonus = max(0, 500 - steps * 2)
        return 1000.0 + time_bonus
    elif outcome == 'defeat':
        return -500.0
    return 0.0


class RewardShaper:
    """
    Main reward shaping class that combines all reward components.

    Args:
        action_weight: Weight for immediate action rewards (default: 1.0)
        strategic_weight: Weight for strategic state improvement (default: 0.5)
        terminal_weight: Weight for terminal episode rewards (default: 1.0)
    """

    def __init__(self,
                 action_weight: float = 1.0,
                 strategic_weight: float = 0.5,
                 terminal_weight: float = 1.0):
        self.action_weight = action_weight
        self.strategic_weight = strategic_weight
        self.terminal_weight = terminal_weight

    def compute_reward(self, prev_state: Dict, action: Tuple, next_state: Dict) -> float:
        """
        Main reward computation method.
        Combines action-level, strategic, and terminal rewards.

        Args:
            prev_state: State before action
            action: Action taken (agent, ability, target)
            next_state: State after action

        Returns:
            Total shaped reward for this transition
        """
        transition = StateTransition(prev_state, action, next_state)

        total_reward = 0.0

        # 1. Action-level rewards (immediate feedback)
        action_reward = compute_action_reward(transition)
        total_reward += action_reward * self.action_weight

        # 2. Strategic-level rewards (state improvement)
        strategic_reward = compute_state_improvement_reward(transition)
        total_reward += strategic_reward * self.strategic_weight

        # 3. Terminal rewards (episode outcome) - only if terminal
        if next_state.get('is_terminal', False):
            outcome = next_state.get('outcome', '')
            # Note: steps parameter would need to be passed in for full terminal reward
            # For now, just use base terminal reward without speed bonus
            if outcome == 'victory':
                terminal_reward = 1000.0
            elif outcome == 'defeat':
                terminal_reward = -500.0
            else:
                terminal_reward = 0.0
            total_reward += terminal_reward * self.terminal_weight

        return total_reward


# Example usage and testing
if __name__ == "__main__":
    # Test scenario: Tank taunts when boss attacks healer
    print("=== Test: Tank Taunt Protection ===")

    prev_state = {
        'boss': {'hp': 400, 'stamina': 200, 'current_target_name': 'healer'},
        'tank': {'hp': 100, 'stamina': 60},
        'healer': {'hp': 30, 'stamina': 100},  # Low HP! Vulnerable!
        'sniper': {'hp': 80, 'stamina': 80}
    }

    action = ('tank', 'taunt', '')

    next_state = {
        'boss': {'hp': 400, 'stamina': 200, 'current_target_name': 'tank'},  # Switched!
        'tank': {'hp': 100, 'stamina': 45},  # Used stamina
        'healer': {'hp': 30, 'stamina': 100},  # Safe now
        'sniper': {'hp': 80, 'stamina': 80}
    }

    shaper = RewardShaper()
    reward = shaper.compute_reward(prev_state, action, next_state)
    print(f"Taunt protection reward: {reward:.2f}")
    print(f"Expected: High positive (200-300+) due to threat_reduction")

    print("\n=== Test: Healing Critical Ally ===")

    prev_state2 = {
        'boss': {'hp': 400, 'stamina': 200, 'current_target_name': 'tank'},
        'tank': {'hp': 100, 'stamina': 60},
        'healer': {'hp': 15, 'stamina': 100},  # Very low HP!
        'sniper': {'hp': 80, 'stamina': 80}
    }

    action2 = ('healer', 'heal', 'healer')  # Self-heal

    next_state2 = {
        'boss': {'hp': 400, 'stamina': 200, 'current_target_name': 'tank'},
        'tank': {'hp': 100, 'stamina': 60},
        'healer': {'hp': 55, 'stamina': 60},  # Healed +40 HP
        'sniper': {'hp': 80, 'stamina': 80}
    }

    reward2 = shaper.compute_reward(prev_state2, action2, next_state2)
    print(f"Critical heal reward: {reward2:.2f}")
    print(f"Expected: High positive (60-100+) due to healing_efficiency")
