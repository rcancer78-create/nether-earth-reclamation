extends RefCounted
## Verified numerical rules from the original Z80 program. See docs/FIDELITY.md.
const COST = [3, 5, 10, 2, 4, 4, 20, 3]
const HEIGHT = [11, 7, 8, 6, 6, 7, 7, 7]
const FACTORY = [6, 6, 6, 5, 4, 3, 2, 1]
const SPEED = [[6, 4, 3], [8, 6, 3], [9, 7, 4]]
const PART_NAMES = ["Бипод", "Гусеницы", "Антиграв", "Пушка", "Ракеты", "Фазер", "Ядерный заряд", "Электроника"]
const RESOURCE_NAMES = ["Общие", "Электроника", "Ядерные", "Фазеры", "Ракеты", "Пушки", "Шасси"]
const ORDERS = ["Остановиться и защищать", "Продвигаться", "Отступать", "Уничтожать роботов", "Уничтожать заводы", "Уничтожать базы", "Захватывать нейтральные заводы", "Захватывать заводы врага", "Захватывать базы врага", "Идти в точку"]
const MAX_ROBOTS = 24
const CAPTURE_TICKS = 144
const DAY_TICKS = 288
const TICK_SECONDS = 0.2

static func valid_parts(mask: int) -> bool:
	var chassis = mask & 7
	var weapons = (mask >> 3) & 15
	return chassis in [1, 2, 4] and weapons != 0 and weapons != 15 and mask >= 0 and mask < 256

static func height(mask: int) -> int:
	var value = 0
	for i in 8:
		if mask & (1 << i): value += HEIGHT[i]
	return value

static func chassis(mask: int) -> int:
	return 0 if mask & 1 else (1 if mask & 2 else 2)

static func payment(stock: Array, mask: int) -> Array:
	if not valid_parts(mask): return []
	var remaining = stock.duplicate()
	for i in 8:
		if not mask & (1 << i): continue
		var kind = FACTORY[i]
		var used = mini(remaining[kind], COST[i])
		remaining[kind] -= used
		remaining[0] -= COST[i] - used
	return remaining if remaining[0] >= 0 else []

static func damage(mask: int, ground: int, weapon: int) -> int:
	return maxi(1, int((60 - height(mask) - ground) / 4.0)) * (weapon - 1)

static func weapon_range(weapon: int, electronics: bool) -> int:
	return (7 if weapon == 4 else 5) + int(electronics)
