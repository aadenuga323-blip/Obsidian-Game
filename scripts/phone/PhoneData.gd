class_name PhoneData
## Catalogue data for the phone apps (Property, Vehicle, Market, Clan, Contacts, GPS).
## Positions are in the Nova Aetheris scene's world space and are placeholders to tune
## once the district layouts are final.

const PROPERTIES: Array[Dictionary] = [
	{"id": "apt_heights_01", "name": "Heights Studio 4B", "type": "Apartment", "district": "The Heights",
		"size": "48 m2 - 1 bed", "rent": 350, "price": 0, "desc": "Compact studio with a balcony over the main avenue. Garage bay included.",
		"position": Vector3(40, 0, -20), "color": Color(0.27, 0.36, 0.52)},
	{"id": "apt_heights_02", "name": "Skyline Loft 12", "type": "Apartment", "district": "The Heights",
		"size": "92 m2 - 2 bed", "rent": 800, "price": 0, "desc": "Top-floor loft, rooftop terrace, private lift to the garage.",
		"position": Vector3(52, 0, -34), "color": Color(0.5, 0.24, 0.55)},
	{"id": "house_heights_01", "name": "Ridge House", "type": "House", "district": "The Heights",
		"size": "180 m2 - 3 bed", "rent": 0, "price": 18500, "desc": "Detached home with driveway and attached double garage on a paved road.",
		"position": Vector3(70, 0, -48), "color": Color(0.72, 0.42, 0.18)},
	{"id": "plot_heights_07", "name": "Building Plot 7", "type": "Plot", "district": "The Heights",
		"size": "400 m2 plot", "rent": 0, "price": 9500, "desc": "Empty land. Design a completely custom house with the Housing Agent after purchase.",
		"position": Vector3(84, 0, -60), "color": Color(0.22, 0.52, 0.36)},
	{"id": "estate_heights_01", "name": "Aurora Clan Estate", "type": "Estate", "district": "The Heights",
		"size": "1,200 m2 - 8 bed", "rent": 0, "price": 120000, "desc": "Clan estate with training lawn, four-car garage and private gate.",
		"position": Vector3(110, 0, -80), "color": Color(0.62, 0.47, 0.16)},
]

const VEHICLES: Array[Dictionary] = [
	{"id": "bike_courier", "name": "Courier Bicycle", "class": "Bicycle", "top_speed": 28, "accel": "n/a", "price": 120,
		"colors": ["Black", "Red", "White"], "desc": "Short deliveries. Free to use on job runs."},
	{"id": "car_city", "name": "Aether Compact", "class": "City car", "top_speed": 95, "accel": "9.8 s", "price": 4200,
		"colors": ["Silver", "Navy", "Crimson", "Black"], "desc": "Affordable first car. Reliable, easy to park."},
	{"id": "van_work", "name": "Foundry Van", "class": "Van", "top_speed": 85, "accel": "12.4 s", "price": 6900,
		"colors": ["White", "Grey"], "desc": "Required for larger or heavier deliveries."},
	{"id": "car_sport", "name": "Velocity GT", "class": "Sports", "top_speed": 165, "accel": "3.9 s", "price": 38000,
		"colors": ["Obsidian", "Cyan", "Gold"], "desc": "Exceptionally fast and sleek. Test track approved."},
	{"id": "car_hyper", "name": "Nexus Hyperion", "class": "Hypercar", "top_speed": 210, "accel": "2.6 s", "price": 145000,
		"colors": ["Obsidian", "Pearl"], "desc": "The fastest thing in Velocity Quarter."},
]

const MARKET: Array[Dictionary] = [
	{"id": "sword_short", "name": "Short Sword", "category": "Weapons", "price": 650, "stock": 12, "desc": "Fast, short reach. Swordsman starter."},
	{"id": "sword_long", "name": "Long Sword", "category": "Weapons", "price": 1100, "stock": 6, "desc": "Slower, longer reach."},
	{"id": "rifle_assault", "name": "Assault Rifle", "category": "Weapons", "price": 1400, "stock": 8, "desc": "Balanced damage and defence."},
	{"id": "rifle_sniper", "name": "Sniper Rifle", "category": "Weapons", "price": 1900, "stock": 4, "desc": "One precise shot from distance."},
	{"id": "bow_std", "name": "Recurve Bow", "category": "Weapons", "price": 900, "stock": 7, "desc": "Mid-range harassment."},
	{"id": "kit_mines", "name": "Mine Kit x3", "category": "Supplies", "price": 420, "stock": 20, "desc": "Engineer chokepoint control."},
	{"id": "tunic_charcoal", "name": "Charcoal Tunic", "category": "Clothing", "price": 300, "stock": 15, "desc": "Fitted tunic, silver trim."},
	{"id": "gear_stealth", "name": "Shadow Wrap", "category": "Clothing", "price": 520, "stock": 9, "desc": "Lightweight, dark, silent."},
	{"id": "decor_lamp", "name": "Aether Floor Lamp", "category": "Decor", "price": 140, "stock": 30, "desc": "Warm light for your new home."},
	{"id": "decor_sofa", "name": "Nexus Sofa", "category": "Decor", "price": 780, "stock": 5, "desc": "Three-seat, charcoal."},
	{"id": "supply_medkit", "name": "Field Medkit", "category": "Supplies", "price": 90, "stock": 40, "desc": "Restores health in The Spire."},
]

const MARKET_CATEGORIES: Array[String] = ["All", "Weapons", "Clothing", "Decor", "Supplies"]

const CONTACTS: Dictionary = {
	"job_agent": {"name": "Rafe Okoro", "role": "Job Agent", "color": Color(0.27, 0.36, 0.52),
		"lines": ["Got a couple of runs open right now. Check the Job Board and tap apply, I'll clear it on my end.",
			"Keep working steady and the bigger contracts open up. I'll call when something good lands."]},
	"housing_agent": {"name": "Mara Vell", "role": "Housing Agent", "color": Color(0.62, 0.47, 0.16),
		"lines": ["Listings in The Heights move fast. Anything you like in the Property App, apply and I'll handle the paperwork.",
			"Once you own a plot we design the house together, room by room. Every choice shows its cost."]},
	"vehicle_dealer": {"name": "Dex Marlowe", "role": "Velocity Quarter Dealer", "color": Color(0.80, 0.50, 0.14),
		"lines": ["Every car in the Quarter is in the Vehicle App. Buy online, I deliver to your driveway or you collect.",
			"The GT is the sweet spot if you want speed without hypercar money."]},
	"clan_leader": {"name": "Sable Kiran", "role": "Clan Leader - Ashfall", "color": Color(0.5, 0.24, 0.55),
		"lines": ["We're scouting a Rank D war next week. Keep your Renown climbing.",
			"Check the Clan Hub, I posted the roster and the map vote."]},
	"mechanic": {"name": "Rook Hale", "role": "Valet & Mechanic", "color": Color(0.80, 0.50, 0.14),
		"lines": ["Hey, how can I help you, or what do you want?"]},
	"foundry": {"name": "Foundry Desk", "role": "Market", "color": Color(0.22, 0.52, 0.36),
		"lines": ["Stock levels are live in the Market App. Orders can be collected or delivered to your home."]},
}

const CLAN := {
	"name": "Ashfall",
	"leader": "Sable Kiran",
	"members": [
		{"name": "Sable Kiran", "class": "Assault", "rank": "C", "online": true},
		{"name": "Juno Hale", "class": "Sniper", "rank": "D", "online": true},
		{"name": "Teo Varga", "class": "Engineer", "rank": "D", "online": false},
		{"name": "Ilse Moor", "class": "Archer", "rank": "C", "online": true},
		{"name": "Kade Rin", "class": "Ninja", "rank": "D", "online": false},
	],
	"messages": [
		"Roster for the Rank D war is open. Reply in the Hub if you are in.",
		"Map vote: Ruins Arena vs Rooftop Arena. Vote closes tonight.",
	],
}

## GPS destinations. Positions are placeholders in the Nova Aetheris scene.
const DESTINATIONS: Array[Dictionary] = [
	{"id": "hub", "name": "Central Nexus - The Hub", "position": Vector3(0, 0, 0)},
	{"id": "job_board", "name": "Public Job Board", "position": Vector3(6, 0, -8)},
	{"id": "training", "name": "Training Grounds", "position": Vector3(-14, 0, -10)},
	{"id": "foundry", "name": "The Foundry - Market", "position": Vector3(-40, 0, 20)},
	{"id": "velocity", "name": "Velocity Quarter - Showrooms", "position": Vector3(45, 0, 30)},
	{"id": "heights", "name": "The Heights - Residential", "position": Vector3(60, 0, -40)},
	{"id": "spire_gate", "name": "Main Gate - Portal to The Spire", "position": Vector3(0, 0, -60)},
]

const FIRST_CALL := "Hey there. I see you just arrived. Fresh off the gates, right? No place to stay, no credits in your pocket... I know what that feels like. You look like someone who's willing to work. Need a job? I've got small tasks - deliveries, simple runs. Nothing dangerous yet, but it'll pay. I've sent someone to pick you up. Look to your right - they're less than a minute away. No need to walk far. They'll bring you straight to me. See you soon."

const RANK_UP_MESSAGE := "Congratulations - you have advanced to your new rank! Your class has grown stronger. New opportunities are now available to you."


static func property(id: String) -> Dictionary:
	for p in PROPERTIES:
		if p["id"] == id:
			return p
	return {}


static func vehicle(id: String) -> Dictionary:
	for v in VEHICLES:
		if v["id"] == id:
			return v
	return {}


static func market_item(id: String) -> Dictionary:
	for m in MARKET:
		if m["id"] == id:
			return m
	return {}
