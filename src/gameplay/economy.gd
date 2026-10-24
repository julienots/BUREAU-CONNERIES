class_name Economy
extends RefCounted
## Fictional money: wallets, purchases (validated), rewards and fines. In solo the
## player wallet is the save file; in multiplayer wallets live on the server only.

signal money_changed(who: String, amount: int)

var wallets: Dictionary = {}        # char_id -> int
var stock: Dictionary = {}          # char_id -> {item_id: count} (owned, not in pocket)
var tier: Dictionary = {}           # char_id -> unlocked tier
var persistent := ""                # char id whose wallet mirrors SaveGame (solo)


func setup_solo(player_id: String) -> void:
	persistent = player_id
	wallets[player_id] = SaveGame.money()
	stock[player_id] = SaveGame.data.owned.duplicate()
	tier[player_id] = int(SaveGame.data.tier_unlocked)


func setup_peer(id: String, money := 80, t := 1) -> void:
	wallets[id] = money
	stock[id] = {}
	tier[id] = t


func money(id: String) -> int:
	return int(wallets.get(id, 0))


func add(id: String, amount: int) -> void:
	wallets[id] = maxi(0, money(id) + amount)
	if id == persistent:
		SaveGame.data.money = wallets[id]
		if amount > 0:
			SaveGame.add_stat("money_earned", amount)
	money_changed.emit(id, wallets[id])


func can_buy(id: String, item_id: String) -> String:
	var it: Dictionary = Data.items.get(item_id, {})
	if it.is_empty():
		return "Objet inconnu."
	if int(it.unlock) >= int(tier.get(id, 1)):
		return "Se débloque au niveau %d (réussis des journées)." % (int(it.unlock) + 1)
	if money(id) < int(it.price):
		return "Pas assez d'argent (%d € requis)." % int(it.price)
	var kind: String = it.kind
	if kind in ["passive", "cosmetic", "coop"] and int(stock.get(id, {}).get(item_id, 0)) > 0:
		return "Tu l'as déjà."
	return ""


## Returns "" on success or the refusal reason. `pocket` receives consumables if possible.
func buy(id: String, item_id: String, pocket: Character) -> String:
	var why := can_buy(id, item_id)
	if why != "":
		return why
	var it: Dictionary = Data.items[item_id]
	add(id, -int(it.price))
	var kind: String = it.kind
	if kind in ["passive", "cosmetic", "coop"]:
		_stock_add(id, item_id, 1)
		if pocket and kind == "passive" and not item_id in pocket.passive:
			pocket.passive.append(item_id)
	else:
		if pocket == null or not pocket.add_item(item_id):
			_stock_add(id, item_id, 1)
	if id == persistent:
		SaveGame.save_game()
	return ""


func take_from_stock(id: String, item_id: String, pocket: Character) -> bool:
	var n := int(stock.get(id, {}).get(item_id, 0))
	if n <= 0 or pocket == null:
		return false
	if not pocket.add_item(item_id):
		return false
	_stock_add(id, item_id, -1)
	return true


func _stock_add(id: String, item_id: String, n: int) -> void:
	if not stock.has(id):
		stock[id] = {}
	stock[id][item_id] = maxi(0, int(stock[id].get(item_id, 0)) + n)
	if stock[id][item_id] == 0:
		stock[id].erase(item_id)
	if id == persistent:
		SaveGame.data.owned = stock[id].duplicate()


## End of day: unused consumables go back to the stock (persisted in solo).
func return_pocket(id: String, pocket: Character) -> void:
	if pocket == null:
		return
	for it in pocket.items:
		if Data.items.has(it):
			_stock_add(id, it, 1)
	pocket.items.clear()
