defmodule CursorParty.GameCore do
  @moduledoc """
  게임의 규칙, 수학적 계산, 상수 정의를 담당하는 순수 함수 모듈입니다.
  데이터베이스나 프로세스 상태에 의존하지 않습니다.
  """

  # ============================================================================
  # 1. 상수 및 데이터 정의
  # ============================================================================

  @max_level 999_999

  # 아이템 정의를 이곳에서 통합 관리
  @shop_items(
    %{
      # --- 기본 능력 (꾸준한 투자 필요) ---
      basic_power: %{
        id: :basic_power,
        name: "Muscle Training",
        icon: "💪",
        desc: "+1 Base Click Damage (Stackable)",
        # 100 -> 50 (초반 진입 장벽 완화)
        base_cost: 50,
        # 1.5 -> 1.3 (가격 상승폭 완화)
        cost_factor: 1.3,
        type: :power,
        value: 1,
        category: :basic
      },
      basic_crit: %{
        id: :basic_crit,
        name: "Sharp Whetstone",
        icon: "💎",
        desc: "+1% Critical Chance (Max 50%)",
        # 5,000 -> 2,000 (접근성 향상)
        base_cost: 2_000,
        # 2.5 -> 2.0 (투자할만하게 변경)
        cost_factor: 2.0,
        type: :passive,
        value: 1,
        category: :basic,
        max_level: 50
      },

      # --- 무기 (티어 간 장벽 완화 및 부드러운 곡선) ---
      # Tier 1: 입문
      w_01_stick: %{
        id: :w_01_stick,
        name: "Wooden Stick",
        icon: "🪵",
        desc: "+5 Power",
        # 1,000 -> 500
        base_cost: 500,
        cost_factor: 1.5,
        type: :power,
        value: 5,
        category: :weapon
      },
      # Tier 2: 초보자
      w_02_dagger: %{
        id: :w_02_dagger,
        name: "Rusty Dagger",
        icon: "🗡️",
        desc: "+50 Power",
        # 50만 -> 15,000 (대폭 완화)
        base_cost: 15_000,
        cost_factor: 1.6,
        type: :power,
        value: 50,
        category: :weapon
      },
      # Tier 3: 중수
      w_03_sword: %{
        id: :w_03_sword,
        name: "Iron Sword",
        icon: "⚔️",
        desc: "+500 Power",
        # 1억 -> 500,000 (현실적인 목표)
        base_cost: 500_000,
        cost_factor: 1.7,
        type: :power,
        value: 500,
        category: :weapon
      },
      # Tier 4: 고수
      w_04_axe: %{
        id: :w_04_axe,
        name: "Battle Axe",
        icon: "🪓",
        # value와 매칭
        desc: "+5,000 Power",
        # 500억 -> 2,000만
        base_cost: 20_000_000,
        cost_factor: 1.8,
        type: :power,
        value: 5_000,
        category: :weapon
      },
      # Tier 5: 영웅
      w_05_gun: %{
        id: :w_05_gun,
        name: "Revolver",
        icon: "🔫",
        desc: "+50,000 Power",
        # 10조 -> 10억
        base_cost: 1_000_000_000,
        cost_factor: 2.0,
        type: :power,
        value: 50_000,
        category: :weapon
      },
      # Tier 6: 전설
      w_06_tank: %{
        id: :w_06_tank,
        name: "Main Battle Tank",
        icon: "🚜",
        desc: "+500,000 Power",
        # 5000조 -> 500억
        base_cost: 50_000_000_000,
        cost_factor: 2.2,
        type: :power,
        value: 500_000,
        category: :weapon
      },
      # Tier 7: 신화
      w_07_laser: %{
        id: :w_07_laser,
        name: "Orbital Laser",
        icon: "🛰️",
        desc: "+5 Million Power",
        # 100경 -> 2조
        base_cost: 2_000_000_000_000,
        cost_factor: 2.5,
        type: :power,
        value: 5_000_000,
        category: :weapon
      },
      # Tier 8: 졸업 (도전적인 목표 유지하되 불가능은 아님)
      w_08_nuke: %{
        id: :w_08_nuke,
        name: "Antimatter Bomb",
        icon: "☢️",
        desc: "+100 Million Power",
        # 1자 -> 500조
        base_cost: 500_000_000_000_000,
        cost_factor: 3.0,
        type: :power,
        value: 100_000_000,
        category: :weapon
      },

      # --- 스킬 (전략 무기) ---
      skill_thunder: %{
        id: :skill_thunder,
        name: "Grimoire: Thunderbolt",
        icon: "⚡",
        desc: "Deal 10x Click DMG (30s CD)",
        # 5천만 -> 100만 (초중반에 재미 요소로 활용 가능하게)
        base_cost: 1_000_000,
        cost_factor: 2.0,
        type: :skill,
        value: 0,
        category: :skill,
        max_level: 1
      },
      skill_rage: %{
        id: :skill_rage,
        name: "Potion: Rage",
        icon: "😡",
        desc: "Double Click Power (Passive)",
        # 5000억 -> 5억 (중반 부스팅용)
        base_cost: 500_000_000,
        cost_factor: 1.0,
        type: :buff,
        value: 2,
        category: :skill,
        max_level: 1
      }
    },
    @boss_list([
      # Tier 1: 미물 (1~10)
      %{emoji: "🦠", name: "Cell"},
      %{emoji: "🪱", name: "Worm"},
      %{emoji: "🪰", name: "Fly"},
      %{emoji: "🦟", name: "Mosquito"},
      %{emoji: "🐜", name: "Ant"},
      %{emoji: "🪳", name: "Cockroach"},
      %{emoji: "🐌", name: "Snail"},
      %{emoji: "🐞", name: "Ladybug"},
      %{emoji: "🐛", name: "Caterpillar"},
      %{emoji: "🦋", name: "Butterfly"},

      # Tier 2: 소동물 (11~20)
      %{emoji: "🐭", name: "Mouse"},
      %{emoji: "🐹", name: "Hamster"},
      %{emoji: "🐰", name: "Rabbit"},
      %{emoji: "🐿️", name: "Chipmunk"},
      %{emoji: "🦔", name: "Hedgehog"},
      %{emoji: "🦇", name: "Bat"},
      %{emoji: "🐍", name: "Snake"},
      %{emoji: "🦎", name: "Lizard"},
      %{emoji: "🐸", name: "Frog"},
      %{emoji: "🐢", name: "Turtle"},

      # Tier 3: 가축 & 야수 (21~30)
      %{emoji: "🐔", name: "Chicken"},
      %{emoji: "🦆", name: "Duck"},
      %{emoji: "🐖", name: "Pig"},
      %{emoji: "🐑", name: "Sheep"},
      %{emoji: "🐐", name: "Goat"},
      %{emoji: "🐕", name: "Dog"},
      %{emoji: "🐈", name: "Cat"},
      %{emoji: "🐂", name: "Ox"},
      %{emoji: "🐎", name: "Horse"},
      %{emoji: "🐃", name: "Buffalo"},

      # Tier 4: 맹수 (31~40)
      %{emoji: "🐗", name: "Boar"},
      %{emoji: "🐺", name: "Wolf"},
      %{emoji: "🦊", name: "Fox"},
      %{emoji: "🐆", name: "Leopard"},
      %{emoji: "🐅", name: "Tiger"},
      %{emoji: "🦁", name: "Lion"},
      %{emoji: "🦍", name: "Gorilla"},
      %{emoji: "🐻", name: "Bear"},
      %{emoji: "🐊", name: "Crocodile"},
      %{emoji: "🦏", name: "Rhino"},

      # Tier 5: 심해 & 고대생물 (41~50)
      %{emoji: "🦈", name: "Shark"},
      %{emoji: "🐋", name: "Whale"},
      %{emoji: "🐙", name: "Kraken"},
      %{emoji: "🦑", name: "Giant Squid"},
      %{emoji: "🦂", name: "Scorpion"},
      %{emoji: "🕷️", name: "Tarantula"},
      %{emoji: "🦖", name: "T-Rex"},
      %{emoji: "🦕", name: "Brachiosaurus"},
      %{emoji: "🦣", name: "Mammoth"},
      %{emoji: "🐲", name: "Dragon Head"},

      # Tier 6: 몬스터 (51~60)
      %{emoji: "👺", name: "Goblin"},
      %{emoji: "👹", name: "Oni"},
      %{emoji: "👻", name: "Ghost"},
      %{emoji: "💀", name: "Skeleton"},
      %{emoji: "👽", name: "Alien"},
      %{emoji: "👾", name: "Invader"},
      %{emoji: "🤖", name: "Robot"},
      %{emoji: "🧟", name: "Zombie"},
      %{emoji: "🧛", name: "Vampire"},
      %{emoji: "🧞", name: "Genie"},

      # Tier 7: 판타지 (61~70)
      %{emoji: "🦄", name: "Unicorn"},
      %{emoji: "🪽", name: "Pegasus"},
      %{emoji: "🦅", name: "Griffin"},
      %{emoji: "🐉", name: "Wyvern"},
      %{emoji: "🐲", name: "Elder Dragon"},
      %{emoji: "🧊", name: "Ice Golem"},
      %{emoji: "🔥", name: "Fire Elemental"},
      %{emoji: "🗿", name: "Stone Giant"},
      %{emoji: "🗽", name: "Titan"},
      %{emoji: "🏰", name: "Living Castle"},

      # Tier 8: 자연재해 & 현상 (71~80)
      %{emoji: "🌪️", name: "Tornado"},
      %{emoji: "🌊", name: "Tsunami"},
      %{emoji: "🌋", name: "Volcano"},
      %{emoji: "⛈️", name: "Storm"},
      %{emoji: "☄️", name: "Meteor"},
      %{emoji: "🌑", name: "Eclipse"},
      %{emoji: "☀️", name: "Sun"},
      %{emoji: "⭐", name: "Star"},
      %{emoji: "🌟", name: "Supernova"},
      %{emoji: "🕳️", name: "Black Hole"},

      # Tier 9: 신화 & 우주 (81~90)
      %{emoji: "🪐", name: "Saturn"},
      %{emoji: "🌌", name: "Galaxy"},
      %{emoji: "🛸", name: "Mothership"},
      %{emoji: "👑", name: "King"},
      %{emoji: "💎", name: "Diamond"},
      %{emoji: "🔱", name: "Poseidon"},
      %{emoji: "⚜️", name: "Emperor"},
      %{emoji: "⚛️", name: "Atom"},
      %{emoji: "☯️", name: "Yin Yang"},
      %{emoji: "🕉️", name: "Om"},

      # Tier 10: 초월적 존재 (91~100)
      %{emoji: "💠", name: "Crystal Core"},
      %{emoji: "🧿", name: "Evil Eye"},
      %{emoji: "🧬", name: "DNA"},
      %{emoji: "🧠", name: "Overmind"},
      %{emoji: "👁️", name: "The Watcher"},
      %{emoji: "🕴️", name: "Void Walker"},
      %{emoji: "👼", name: "Seraphim"},
      %{emoji: "👿", name: "Archdemon"},
      %{emoji: "💊", name: "The Pill"},
      %{emoji: "💻", name: "The Server"}
    ])
  )

  def get_boss_info(level) do
    list_length = length(@boss_list)
    index = rem(level - 1, list_length)
    cycle = div(level - 1, list_length)

    base_info = Enum.at(@boss_list, index)

    # 칭호(Suffix) 결정 (영어 원문)
    suffix =
      case cycle do
        0 -> ""
        1 -> " (Ascended)"
        2 -> " (God)"
        3 -> " (Void)"
        4 -> " (Eternal)"
        _ -> " (Tier #{cycle})"
      end

    # 이름을 합치지 않고 :suffix 키로 따로 반환!
    Map.put(base_info, :suffix, suffix)
  end

  def get_shop_items, do: @shop_items
  def get_item(id), do: @shop_items[id]
  def max_level, do: @max_level

  # ============================================================================
  # 2. 계산 로직 (Pure Functions)
  # ============================================================================

  # 아이템 구매 비용 계산 (내부용)
  defp calculate_cost(base_cost, factor, current_level) do
    floor(base_cost * :math.pow(factor, current_level))
  end

  # [신규] UI 표시용 비용 계산 (만렙 처리 포함)
  def get_item_cost(item_id, current_level) do
    item = @shop_items[item_id]

    if item do
      # 만렙이면 비용 대신 :max 반환
      max_level = Map.get(item, :max_level, :infinity)

      if max_level != :infinity and current_level >= max_level do
        :max
      else
        calculate_cost(item.base_cost, item.cost_factor, current_level)
      end
    else
      0
    end
  end

  # 유저의 현재 스탯(Power) 계산
  def calculate_stats(user_items) do
    base =
      Enum.reduce(@shop_items, %{power: 1, crit_chance: 0, power_mult: 1}, fn {k, item_def},
                                                                              acc ->
        lvl = Map.get(user_items, k, 0)

        if lvl > 0 do
          case item_def.type do
            :power -> %{acc | power: acc.power + lvl * item_def.value}
            # :auto 케이스 제거됨
            :passive -> %{acc | crit_chance: min(50, acc.crit_chance + lvl * item_def.value)}
            :buff -> %{acc | power_mult: acc.power_mult + lvl * (item_def.value - 1)}
            _ -> acc
          end
        else
          acc
        end
      end)

    final_power = base.power * base.power_mult

    # auto 필드 제거
    Map.delete(base, :power_mult)
    |> Map.put(:power, final_power)
  end

  # [삭제] calculate_auto_damage 함수 제거됨 (더 이상 사용 안 함)

  # 보스 다음 레벨 체력 계산
  def calculate_boss_hp(level) do
    base = 2000
    growth_rate = 1.20
    hp = base * :math.pow(growth_rate, level - 1)
    linear_bonus = (level - 1) * 500
    round(hp) + linear_bonus
  end

  # 타격 계산
  def calculate_hit(stats) do
    is_crit = :rand.uniform(100) <= 15 + stats.crit_chance

    damage =
      if is_crit do
        stats.power * 2
      else
        stats.power
      end

    {damage, is_crit}
  end

  # 아이템 구매 가능 여부 및 결과 계산
  def try_buy_item(current_gold, user_items, item_id) do
    item = @shop_items[item_id]

    if item do
      current_level = Map.get(user_items, item_id, 0)

      # [신규 로직] max_level 체크
      max_level = Map.get(item, :max_level, :infinity)

      cond do
        # 1. 이미 만렙인 경우
        max_level != :infinity and current_level >= max_level ->
          {:error, :max_level_reached}

        # 2. 돈이 충분한 경우
        true ->
          cost = calculate_cost(item.base_cost, item.cost_factor, current_level)

          if current_gold >= cost do
            new_gold = current_gold - cost
            new_items = Map.put(user_items, item_id, current_level + 1)
            {:ok, new_gold, new_items, current_level + 1}
          else
            {:error, :not_enough_gold}
          end
      end
    else
      {:error, :item_not_found}
    end
  end
end
