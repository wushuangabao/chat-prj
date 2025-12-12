import time
import random

# --- 核心常量 ---

class State:
    IDLE = "站立"      # 寻找下一个招式
    MOVE = "移动"      # 接近敌人
    WINDUP = "前摇"    # 蓄力/起手（脆弱期，受击会被打断）
    ACTIVE = "判定"    # 伤害/效果生效期
    RECOVERY = "后摇"  # 收招（如果有连招可取消）
    STUNNED = "僵直"   # 被打断/受击后的硬直状态

class ActionType:
    ATTACK = "攻击"
    DEFEND = "格挡"
    DODGE = "闪避"
    WAIT = "观望"

# --- 节点系统 (行为树/链表) ---

class Node:
    def __init__(self, name):
        self.name = name

class ActionNode(Node):
    """【动】节点：包含具体的时间轴参数"""
    def __init__(self, name, action_type, windup=0.3, active=0.1, recovery=0.5, power=10, toughness=0.0, cost=10.0, atk_range=1.0, dash=0.0, knockback=0.5, backdash=0.0):
        super().__init__(name)
        self.action_type = action_type
        # 时间参数 (秒)
        self.windup = windup      # 前摇：此期间受击会被打断
        self.active = active      # 判定：伤害生效窗口
        self.recovery = recovery  # 后摇：动作结束后的僵直
        
        self.power = power
        self.toughness = toughness # 韧性：减少受击硬直时间
        self.cost = cost # 耐力消耗
        
        # 距离参数 (米)
        self.atk_range = atk_range   # 攻击距离
        self.dash = dash             # 突进距离 (在前摇期间完成)
        self.knockback = knockback   # 击退距离
        self.backdash = backdash     # 后撤距离 (闪避用)
        
        self.next_node_name = None

    def set_next(self, node_name):
        self.next_node_name = node_name
        return self

class ConditionNode(Node):
    """【判】节点：瞬时逻辑判断，不消耗时间"""
    def __init__(self, name, check_func):
        super().__init__(name)
        self.check_func = check_func
        self.true_node_name = None
        self.false_node_name = None

    def set_branches(self, true_name, false_name):
        self.true_node_name = true_name
        self.false_node_name = false_name
        return self

# --- 角色类 ---

class Fighter:
    def __init__(self, name, hp, root_node_name="start"):
        self.name = name
        self.max_hp = hp
        self.hp = hp
        
        # 行为树/图存储
        self.nodes = {} 
        self.root_node_name = root_node_name
        
        # 运行时状态
        self.current_node_name = root_node_name
        self.state = State.IDLE
        self.state_timer = 0.0     # 当前状态已持续时间
        self.current_action_node = None # 当前正在执行的动作节点引用
        
        # 韧性系统
        self.poise_damage_accumulator = 0.0 # 累积受到的削韧值
        self.last_hit_time = -999.0 # 上次受击时间
        
        # 耐力系统
        self.max_stamina = 100.0
        self.stamina = 100.0
        self.stamina_regen = 20.0 # 每秒恢复
        
        # 战斗统计
        self.log_buffer = []

    def log(self, msg):
        print(f"[{self.name}] {msg}")

    def add_node(self, node):
        self.nodes[node.name] = node
        return node

    def take_damage(self, damage, current_time, is_interrupt=False):
        self.hp -= damage
        self.last_hit_time = current_time
        
        if is_interrupt:
            # 特殊检查：闪避动作不可被打断
            if self.current_action_node and self.current_action_node.action_type == ActionType.DODGE:
                 self.log(f"被击中! (伤害 {damage}) -> 闪避中，免疫打断!")
                 return

            # 累积削韧值
            self.poise_damage_accumulator += damage
            
            # 计算韧性
            toughness_value = 0.0
            if self.current_action_node:
                # 只有在 WINDUP 和 ACTIVE 阶段才有霸体保护
                # 后摇(RECOVERY)阶段视为失去架势，韧性为0，极易被破防
                if self.state in [State.WINDUP, State.ACTIVE]:
                     toughness_value = self.current_action_node.toughness
            
            # 破防判定
            if self.poise_damage_accumulator > toughness_value:
                # 2. 硬直计算：使用【当前伤害】
                actual_stun = damage * 0.05
                
                self.log(f"被击中! (伤害 {damage}, 累积削韧 {self.poise_damage_accumulator} > 韧性 {toughness_value}) -> 招式被打断! 陷入僵直 {actual_stun:.2f}s!")
                self.enter_stunned(actual_stun)
                self.poise_damage_accumulator = 0.0 # 被打断后，削韧值清零（重置架势）
            else:
                self.log(f"被击中! (伤害 {damage}, 累积削韧 {self.poise_damage_accumulator} <= 韧性 {toughness_value}) -> 霸体抗住!")
        else:
            self.log(f"被击中! (伤害 {damage})")
            # 如果不是打断（比如在后摇或僵直时被打），可能只是扣血

    def enter_stunned(self, duration):
        self.state = State.STUNNED
        self.state_timer = 0.0
        self.stun_duration = duration
        self.current_action_node = None # 清除当前动作
        # 重点：被打断后，思维重置，下次醒来从根节点重新开始
        self.current_node_name = self.root_node_name

    def get_next_action_node(self, enemy):
        """递归执行逻辑节点，直到找到一个动作节点，或者没有节点为止"""
        steps = 0
        while steps < 100: # 防止无限循环
            if self.current_node_name not in self.nodes:
                self.current_node_name = self.root_node_name # 循环回根
            
            node = self.nodes[self.current_node_name]
            
            if isinstance(node, ActionNode):
                return node
            
            elif isinstance(node, ConditionNode):
                # 瞬时执行逻辑判断
                result = node.check_func(self, enemy)
                # self.log(f"思考: {node.name}? -> {result}")
                self.current_node_name = node.true_node_name if result else node.false_node_name
            
            steps += 1
        return None

    def update(self, dt, enemy, current_time, dist_mgr):
        """帧更新"""
        if self.hp <= 0: return

        self.state_timer += dt
        
        # 韧性恢复逻辑... (省略)

        # 耐力恢复逻辑
        if self.state in [State.IDLE, State.RECOVERY, State.MOVE]:
             self.stamina = min(self.max_stamina, self.stamina + self.stamina_regen * dt)

        # --- 1. 僵直状态 ---
        if self.state == State.STUNNED:
            # 尝试受身逻辑
            # 条件: 僵直剩余时间 > 0.3s 且 耐力 > 40
            remaining_stun = self.stun_duration - self.state_timer
            ukemi_cost = 40.0
            
            if remaining_stun > 0.3 and self.stamina >= ukemi_cost:
                self.stamina -= ukemi_cost
                self.state = State.IDLE
                self.state_timer = 0
                self.log(f"发动【受身】! 消耗 {ukemi_cost} 耐力，解除僵直!")
                return

            if self.state_timer >= self.stun_duration:
                self.state = State.IDLE
                self.state_timer = 0
                self.log("从僵直中恢复")
            return

        # --- 2. 空闲状态 (思考下一招) ---
        if self.state == State.IDLE:
            next_action = self.get_next_action_node(enemy)
            if next_action:
                # 检查距离
                # 如果 atk_range <= 0，视为原地技能/无限距离，不需要移动
                effective_range = next_action.atk_range + next_action.dash
                if next_action.atk_range > 0 and dist_mgr.distance > effective_range:
                    # 距离太远，进入移动状态
                    self.current_action_node = next_action # 记住想用的招式
                    self.state = State.MOVE
                    self.state_timer = 0
                    self.log(f"距离过远 ({dist_mgr.distance:.1f}m > {effective_range:.1f}m)，开始接近...")
                    return

                # 距离合适，检查耐力
                if self.stamina >= next_action.cost:
                    self.stamina -= next_action.cost
                    self.current_action_node = next_action
                    self.state = State.WINDUP
                    self.state_timer = 0
                    self.poise_damage_accumulator = 0.0 # 新动作开始，重置架势/削韧值
                    self.log(f"起手: 【{next_action.name}】 (前摇 {next_action.windup}s, 突进 {next_action.dash}m)")
                else:
                    # 耐力不足，休息
                    pass
            return

        # --- 2.5 移动状态 ---
        if self.state == State.MOVE:
            # 移动速度 3m/s
            move_speed = 3.0
            dist_mgr.distance -= move_speed * dt
            
            # 检查是否进入射程
            node = self.current_action_node
            effective_range = node.atk_range + node.dash
            
            if dist_mgr.distance <= effective_range:
                # 进入射程，直接转入起手
                # 再次检查耐力（防止移动过程中耐力回满又立刻被打空之类的情况，虽然移动也会回耐）
                if self.stamina >= node.cost:
                    self.stamina -= node.cost
                    self.state = State.WINDUP
                    self.state_timer = 0
                    self.poise_damage_accumulator = 0.0 # 新动作开始，重置架势
                    self.log(f"进入射程 ({dist_mgr.distance:.1f}m)! 起手: 【{node.name}】")
                else:
                    self.state = State.IDLE # 耐力不够，转回IDLE喘息
            
            # 距离最小限制
            if dist_mgr.distance < 0.5: dist_mgr.distance = 0.5
            return

        # --- 3. 动作执行流程 (前摇 -> 判定 -> 后摇) ---
        if self.current_action_node:
            node = self.current_action_node
            
            # [阶段 A: 前摇 WINDUP]
            if self.state == State.WINDUP:
                # 前摇突进
                if node.dash > 0:
                    dash_speed = node.dash / node.windup
                    dist_mgr.distance -= dash_speed * dt
                    if dist_mgr.distance < 0.5: dist_mgr.distance = 0.5
                
                # 闪避后撤 (在 ACTIVE 阶段执行比较合理，或者在 WINDUP 末尾瞬间完成？)
                # 一般后撤步是瞬间爆发的。我们把它放在 ACTIVE 开始的一瞬间执行，或者平滑执行。
                # 既然是 Timeline，我们可以在 WINDUP 期间平滑后撤，也可以在 ACTIVE 瞬间拉开。
                # 考虑到“闪避”是躲技能，应该尽早拉开。我们放在 WINDUP 期间平滑后撤。
                if node.backdash > 0:
                    backdash_speed = node.backdash / node.windup
                    dist_mgr.distance += backdash_speed * dt
                    # self.log(f"后撤中... 距离 {dist_mgr.distance:.1f}")

                if self.state_timer >= node.windup:
                    # 前摇结束，进入判定帧
                    # **关键机制：闪避判定**
                    # 如果此时距离 > 攻击距离，说明对方跑了，招式挥空
                    # 注意：对于原地技能(atk_range<=0)，不进行挥空判定
                    if node.atk_range > 0 and dist_mgr.distance > node.atk_range:
                        self.log(f"【{node.name}】 距离不够 ({dist_mgr.distance:.1f}m > {node.atk_range}m)，挥空! 自动中断!")
                        # 挥空惩罚：进入后摇，或者直接结束（按用户要求：自动中断无僵直 -> 转IDLE）
                        # 用户原话：“招式自动中断（当然这种主动中断不会陷入僵直）”
                        self.state = State.IDLE
                        self.state_timer = 0
                        self.current_action_node = None # 清除动作
                        self.poise_damage_accumulator = 0.0 # 动作结束，韧性重置
                    else:
                        self.state = State.ACTIVE
                        self.state_timer = 0
                        self.perform_hit_check(node, enemy, current_time, dist_mgr)

            # [阶段 B: 判定 ACTIVE]
            elif self.state == State.ACTIVE:
                if self.state_timer >= node.active:
                    # 判定结束，进入后摇
                    # **连招取消后摇机制**: 
                    # 如果当前节点有后续连接，直接跳过后摇 (或者大幅缩短)
                    if node.next_node_name:
                         self.log(f"动作完成 -> 连招取消后摇!")
                         self.state = State.IDLE
                         self.state_timer = 0
                         self.current_node_name = node.next_node_name # 推进指针
                         # 连招切换动作，也视为新动作开始，韧性重置
                         self.poise_damage_accumulator = 0.0
                    else:
                        self.state = State.RECOVERY
                        self.state_timer = 0

            # [阶段 C: 后摇 RECOVERY]
            elif self.state == State.RECOVERY:
                if self.state_timer >= node.recovery:
                    self.state = State.IDLE
                    self.state_timer = 0
                    # 动作彻底结束，推进到下一节点（如果是None就会在IDLE里重置回root）
                    self.current_node_name = node.next_node_name
                    # 动作切换，韧性重置
                    self.poise_damage_accumulator = 0.0
                    # self.log("动作结束，韧性条重置")

    def perform_hit_check(self, node, enemy, current_time, dist_mgr):
        """在 ACTIVE 帧触发的瞬间调用"""
        self.log(f"【{node.name}】 出招!")
        
        if node.action_type == ActionType.ATTACK:
            # 命中判定
            hit = True
            is_interrupt = False
            
            # 1. 对方在闪避?
            if enemy.state == State.ACTIVE and enemy.current_action_node.action_type == ActionType.DODGE:
                hit = False
                self.log(">> 攻击被对方闪避!")
            
            # 2. 对方在格挡?
            elif enemy.state == State.ACTIVE and enemy.current_action_node.action_type == ActionType.DEFEND:
                damage = int(node.power * 0.2) # 格挡减伤
                enemy.take_damage(damage, current_time, is_interrupt=False) # 格挡不会被打断
                self.log(f">> 攻击被格挡，造成 {damage} 点伤害")
                # 格挡也要计算击退，虽然可能减半
                # 同样应用新的击退逻辑：推到 knockback * 0.5 的位置
                block_knockback = node.knockback * 0.5
                if dist_mgr.distance < block_knockback:
                    dist_mgr.distance = block_knockback
                hit = False # 没打实
                
            if hit:
                # 3. 关键机制：打断判定 (Interrupt)
                # 如果敌人处于 前摇(WINDUP) 或 后摇(RECOVERY)，会被打断
                if enemy.state in [State.WINDUP, State.RECOVERY]:
                    is_interrupt = True
                    self.log(">> 抓住了对方的破绽! 打断!")
                
                enemy.take_damage(node.power, current_time, is_interrupt)
                
                # 4. 击退效果
                # 机制修改：击退不再是累加距离，而是强制将双方距离拉开到 node.knockback
                # 只有当当前距离小于击退距离时，才会被推开
                if node.knockback > 0:
                    if dist_mgr.distance < node.knockback:
                        dist_mgr.distance = node.knockback
                        # self.log(f"将对方击退至 {node.knockback}m")

# --- 战斗引擎 ---

class DistanceManager:
    def __init__(self, initial_distance):
        self.distance = initial_distance

def run_timeline_simulation():
    # 初始化
    dist_mgr = DistanceManager(initial_distance=3.0) # 初始距离3米
    
    # 设定: 赵无极用重剑，前摇长，伤害高
    p1 = Fighter("赵无极", 200)
    # 设定: 张无忌用快剑，前摇短，伤害低，容易打断别人
    p2 = Fighter("张无忌", 200)

    # === P1 赵无极: 蓄力重击流 (增加韧性) ===
    # 逻辑: 只有一招 "开山斧"，前摇1.0秒，伤害50
    # 这是一个非常危险的招式，但拥有高韧性 (25.0)，能抗住约25点伤害（相当于抗住1次轻攻击，第2次破防）
    # 攻击距离: 1.5m, 突进: 0.5m (总有效距离 2.0m), 击退: 2.0m
    heavy_atk = ActionNode("开山斧", ActionType.ATTACK, windup=1.0, active=0.2, recovery=1.0, power=50, toughness=25.0, cost=30.0, atk_range=1.5, dash=0.5, knockback=2.0)
    p1.add_node(heavy_atk).set_next("start") # 循环
    p1.nodes["start"] = heavy_atk

    # === P2 张无忌: 敏捷连击流 ===
    # 逻辑: 快速刺击 (前摇0.3s) -> 快速刺击 -> 闪避
    # 攻击距离: 0.8m, 突进: 1.0m (总有效距离 1.8m), 击退: 0.2m
    light_atk1 = ActionNode("太极剑·刺", ActionType.ATTACK, windup=0.3, active=0.1, recovery=0.3, power=15, cost=15.0, atk_range=0.8, dash=1.0, knockback=0.2)
    light_atk2 = ActionNode("太极剑·挑", ActionType.ATTACK, windup=0.3, active=0.1, recovery=0.3, power=15, cost=15.0, atk_range=0.8, dash=0.5, knockback=0.2)
    # 闪避: 突进=0, 后撤=2.0m (迅速拉开距离)
    dodge = ActionNode("梯云纵", ActionType.DODGE, windup=0.1, active=0.5, recovery=0.2, power=0, cost=20.0, atk_range=0, dash=0, knockback=0, backdash=2.0)
    
    p2.add_node(light_atk1).set_next("atk2")
    p2.add_node(light_atk2).set_next("dodge")
    p2.add_node(dodge).set_next("start")
    
    # 修正字典键名
    p2.nodes["start"] = light_atk1
    p2.nodes["atk2"] = light_atk2
    p2.nodes["dodge"] = dodge

    # === 开始模拟 ===
    print(f"--- 战斗开始: {p1.name} (重剑) VS {p2.name} (快剑) ---")
    print(f"初始距离: {dist_mgr.distance}m")
    
    dt = 0.1 # 时间步长 0.1秒
    time_elapsed = 0.0

    while p1.hp > 0 and p2.hp > 0 and time_elapsed < 60.0: # 限时60秒
        # 双方更新状态
        p1.update(dt, p2, time_elapsed, dist_mgr)
        p2.update(dt, p1, time_elapsed, dist_mgr)
        
        # 生成当前帧的状态信息
        current_status_msg = f"   {p1.name}[{p1.state} SP:{p1.stamina:.0f}] HP:{p1.hp}  ||  {p2.name}[{p2.state} SP:{p2.stamina:.0f}] HP:{p2.hp} || Dist:{dist_mgr.distance:.1f}m"
        
        print(f"\n[T={time_elapsed:.1f}s]")
        print(current_status_msg)
        
        # time.sleep(0.01)
        time_elapsed += dt

    print("\n--- 战斗结束 ---")
    if p1.hp <= 0: print(f"{p2.name} 获胜!")
    elif p2.hp <= 0: print(f"{p1.name} 获胜!")
    else: print("时间到，平局")

if __name__ == "__main__":
    run_timeline_simulation()
