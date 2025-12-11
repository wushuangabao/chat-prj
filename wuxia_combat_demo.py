import time
import random

# --- 核心定义 ---

class ActionType:
    ATTACK = "攻击"
    DEFEND = "格挡"
    DODGE = "闪避"
    WAIT = "观望"

class Node:
    """招式节点"""
    def __init__(self, name):
        self.name = name
    
    def execute(self, me, enemy):
        """返回 (Result, Next_Node_Name)"""
        pass

class ActionNode(Node):
    """【动】节点：执行具体动作"""
    def __init__(self, name, action_type, power=10, speed=5):
        super().__init__(name)
        self.action_type = action_type
        self.power = power
        self.speed = speed
        self.next_node = None # 默认下一招

    def set_next(self, node_name):
        self.next_node = node_name
        return self

    def execute(self, me, enemy):
        # 更新自身状态
        me.current_action = self.action_type

        # 简单的命中判定逻辑
        hit_chance = 0.8
        if enemy.current_action == ActionType.DEFEND:
            hit_chance = 0.2
        elif enemy.current_action == ActionType.DODGE:
            hit_chance = 0.0
        
        success = False
        damage = 0
        
        if self.action_type == ActionType.ATTACK:
            if random.random() < hit_chance:
                success = True
                damage = self.power
                enemy.hp -= damage
                log(f"  > {me.name} 【{self.name}】 命中! 造成 {damage} 点伤害")
            else:
                log(f"  > {me.name} 【{self.name}】 被化解/未命中!")
        elif self.action_type == ActionType.DEFEND:
            success = True # 防御总是成功的动作（虽然效果取决于敌人）
            log(f"  > {me.name} 架起防御姿态")
        else:
            log(f"  > {me.name} 正在 {self.action_type}")
            success = True

        return success, self.next_node

class ConditionNode(Node):
    """【判】节点：逻辑分支"""
    def __init__(self, name, check_func):
        super().__init__(name)
        self.check_func = check_func
        self.true_node = None
        self.false_node = None

    def set_branches(self, true_name, false_name):
        self.true_node = true_name
        self.false_node = false_name
        return self

    def execute(self, me, enemy):
        result = self.check_func(me, enemy)
        next_node = self.true_node if result else self.false_node
        log(f"  ? {me.name} 思考: {self.name}? -> {'是' if result else '否'}")
        return result, next_node

# --- 角色与系统 ---

def log(msg):
    print(msg)

class Fighter:
    def __init__(self, name, hp):
        self.name = name
        self.hp = hp
        self.nodes = {} # 存储所有招式节点
        self.current_node_name = "start" # 当前执行到的节点
        self.current_action = ActionType.WAIT
    
    def add_node(self, node):
        self.nodes[node.name] = node
        return node

    def step(self, enemy):
        if self.hp <= 0: return
        
        if self.current_node_name not in self.nodes:
            # 招式链结束，重置回开头
            self.current_node_name = "start"
        
        current_node = self.nodes[self.current_node_name]
        
        # 执行节点逻辑
        # 注意：这里简化了，实际游戏中【动】节点会消耗时间帧，而【判】节点是瞬时的
        _, next_name = current_node.execute(self, enemy)
        
        self.current_node_name = next_name

# --- 战斗模拟 ---

def run_simulation():
    p1 = Fighter("赵无极 (莽夫流)", 100)
    p2 = Fighter("张三丰 (太极AI)", 100)

    # === 构建 P1 的招式链: 莽夫三板斧 ===
    # 逻辑: 刺 -> 砍 -> 劈 -> (循环)
    p1.add_node(ActionNode("start", ActionType.ATTACK, power=10)).set_next("move2")
    p1.add_node(ActionNode("move2", ActionType.ATTACK, power=15)).set_next("move3")
    p1.add_node(ActionNode("move3", ActionType.ATTACK, power=20)).set_next("start")

    # === 构建 P2 的招式链: 智能反击流 ===
    # 逻辑: 
    # start: 敌人是否在攻击? 
    #   Yes -> 格挡 -> (下一招)反击
    #   No  -> 试探性攻击
    
    # 1. 定义节点
    check_enemy_atk = ConditionNode("敌方在攻击吗", lambda m, e: e.current_action == ActionType.ATTACK)
    defend_move = ActionNode("太极·云手(防)", ActionType.DEFEND)
    counter_atk = ActionNode("太极·搬拦捶(反)", ActionType.ATTACK, power=25) # 反击伤害高
    poke_atk = ActionNode("武当剑(试探)", ActionType.ATTACK, power=5)

    # 2. 连接节点
    p2.add_node(check_enemy_atk).set_branches("defend", "poke")
    p2.add_node(defend_move).set_next("counter")
    p2.add_node(counter_atk).set_next("start") # 反击完回起点
    p2.add_node(poke_atk).set_next("start")    # 试探完回起点
    
    # 修正字典键名匹配
    p2.nodes["start"] = check_enemy_atk
    p2.nodes["defend"] = defend_move
    p2.nodes["counter"] = counter_atk
    p2.nodes["poke"] = poke_atk

    # === 开始战斗 ===
    print(f"--- 战斗开始: {p1.name} VS {p2.name} ---")
    
    for turn in range(1, 11): # 模拟10个回合
        if p1.hp <= 0 or p2.hp <= 0: break
        
        print(f"\n[回合 {turn}]")
        # 双方同时行动 (简化处理，先结算P1动作更新状态，再结算P2)
        # 实际游戏中应该是基于时间轴的并发
        
        # P1 行动
        p1.step(p2)
        
        # P2 行动 (P2会读取P1当前状态)
        p2.step(p1)
        
        print(f"状态: {p1.name} HP:{p1.hp} | {p2.name} HP:{p2.hp}")
        time.sleep(0.5)

    print("\n--- 战斗结束 ---")
    if p1.hp > p2.hp: print(f"胜者: {p1.name}")
    elif p2.hp > p1.hp: print(f"胜者: {p2.name}")
    else: print("平局")

if __name__ == "__main__":
    run_simulation()