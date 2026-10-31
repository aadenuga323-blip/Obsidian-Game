# In-Game Phone System

Implements the **"Your In-Game Phone System"** section of OBSIDIAN.docx on top of the
existing `Globalvar` and `JobManager` autoloads. No scene edits are required: the phone is
an autoload (`Phone`) that draws itself in any scene.

## Try it
- Run the project, press **P** (or tap the **PHONE** button, bottom-right).
- After the gate intro, the Job Agent **calls you** with the Step Three script. Answer and
  tap *Open Job Board*.
- Apply to a job: a GPS beacon appears in the world; walking into it completes delivery jobs.
- Headless regression test: `godot --headless --path . res://tests/phone_smoke_test.tscn`

## Apps (all from the document)
| App | What it does |
|---|---|
| **Job Board** | Lists every available job with pay, distance (live, from the player), duration and type. Sort by pay / distance / duration, filter by type, *Apply* → `JobManager.accept_job`, GPS guides you. Active job shows progress and can be cancelled. |
| **Property** | Heights apartments (rent), houses, plots and a clan estate. Photo tile, size, price, confirm step. After purchase the **Housing Agent calls**; a plot starts a construction timer and the agent calls again when the doors open. |
| **Vehicle** | Velocity Quarter catalogue with specs and colour swatches. Buy with *Deliver to driveway* (delivery notification) or *Collect at dealer* (GPS to the showroom). |
| **Market** | Foundry stock by category with live stock levels. Order to collect (GPS to The Foundry) or deliver (needs a home). Items go to `Globalvar.inventory_items`. |
| **Clan Hub** | Members online, leader messages, war invitations with Accept / Decline, Renown progress and reputation. |
| **GPS** | Any district, the Hub, the gate, your home or your job as destination. Spawns a `GpsMarker` beacon; `Phone.destination_set` / `destination_cleared` signals are there for the mini-map. |
| **Stats & Wallet** | Rank badge with progress to next rank, Renown, Points, credits, reputation, class, jobs, holdings. |
| **Contacts & Calls** | Contacts save automatically (job agent, housing agent, dealer, clan leader, Foundry). Call any of them; incoming calls show Answer / Ignore and play the caller's line. |
| **Notifications** | Job offers, deliveries, construction, rank-ups, invitations; unread badge on the phone button. |

## Player-to-player communication (Session autoload)
- **Contacts > Players in session** lists everyone in the session with **Message** and **Call**.
- **Message** opens a chat thread (bubbles, composer, Enter to send). Incoming texts raise a
  notification and an unread badge on the player's card.
- **Call** rings the other player; they get an **Incoming call** screen with Answer / Decline.
  While connected the call screen shows a timer, a microphone level meter, Mute and End call.
- Transport is Godot's high-level multiplayer: texts and call signalling are reliable RPCs,
  microphone audio is captured with `AudioEffectCapture`, sent as 16 kHz 16-bit PCM over
  unreliable-ordered RPC and played back through an `AudioStreamGenerator`. Attach any
  `MultiplayerPeer` (ENet, WebRTC) to `multiplayer.multiplayer_peer` and it works between
  real players; with no peer a simulated roster answers texts and calls so everything can
  be exercised offline. `audio/driver/enable_input` is on in project settings for the mic.

## Automated valet service (Valet autoload, contact "Rook Hale - Valet & Mechanic")
Call Rook from Contacts or the Vehicle app. When he answers, his recorded greeting plays
("Hey, how can I help you, or what do you want?" - `audio/phone/rook_greeting.wav`; the
other `rook_*.wav` lines voice his Request / Fix / Return confirmations and the repair
callback). Once the line has been spoken the call screen shows a bar:
- **Request** - lists your cars with their status. Pick one: an NPC spawns in it at a nearby
  road node (place `Marker3D` nodes in the `road_node` group along streets; without any, a
  spot ~40 m away on the ground is used), drives to your position, parks six metres away,
  climbs out and walks off. The car is then yours to enter with E.
- **Return** - the delivered car disappears immediately.
- **Fix** - lists damaged cars (collisions above ~6 m/s add damage). Picking one moves it to
  the mechanic's service queue; repairs run one at a time (0.6 s per damage percent, 8 s
  minimum), the Vehicle app and the call screen show the remaining time, and Rook calls
  back when it is ready. Cars in service cannot be requested.
- Buying a car with "Deliver to driveway" now uses the same valet delivery.
- The driver (`ValetDriver`) moves the frozen body kinematically along the ground, detects the
  car's front from the steering wheels' positions, and hands the body back to physics on
  arrival, so it does not depend on the vehicle's suspension or engine tuning.

## Code map
- `scripts/phone/PhoneManager.gd` — the `Phone` autoload (UI, apps, calls, messages, valet bar, notifications, GPS).
- `scripts/phone/SessionManager.gd` — the `Session` autoload: roster, text RPCs, voice call signalling and audio streaming.
- `scripts/phone/ValetService.gd` + `ValetDriver.gd` — the `Valet` autoload: request / return / fix, service queue, NPC chauffeur.
- `scripts/phone/PhoneData.gd` — catalogues: properties, vehicles, market, contacts, clan, destinations.
  Positions are placeholders in the Nova Aetheris scene; tune them once districts are laid out.
- `scripts/phone/PhoneTheme.gd` — Rajdhani font + shared styles.
- `scripts/phone/GpsMarker.gd` — world beacon, emits `arrived` when a `players`-group node is within 4 m.
- `scripts/Autoload/Globalvar.gd` — added wallet signals, reputation, holdings, contacts, destination, vehicle damage/colours. Rank comes from the existing `RankManager`.
- `scripts/QuestFolder/QuestSystem/QuestData.gd` — new optional fields for the Job Board: client, job_type, pay (credits), distance_m, duration_min, has_location + location (GPS beacon). Three sample quests added in `ResourcesFilesTres/quests/`.
- `scripts/QuestFolder/QuestSystem/JobManager.gd` — `available_jobs()`, `job_pay()` (reputation-scaled), `cancel_job()`, `last_payout`; completion also pays credits.
- `scripts/area/maingate.gd` — one line: rings the first call after the gate intro.
- `project.godot` — `Phone` autoload and the `phone` input action (P).

## Public API for other systems
```gdscript
Phone.notify("Tournament starting", "Rank D bracket opens in 2 minutes.", "invite")
Phone.invite("tournament", "Rank D Tournament", "Ruins Arena. 16 players.")   # Accept/Decline on the phone
Phone.incoming_call("clan_leader", "War is on tonight. You in?", "Open Clan Hub", "clan")
Phone.set_destination(Vector3(40, 0, -20), "Skyline Villa")
Phone.open("jobs")
Session.send_text(player_id, "Meet at the Hub?")      # Session.players lists ids
Session.start_call(player_id)                          # voice call; Phone shows the screen
Valet.request("car_city")  /  Valet.return_vehicle("car_city")  /  Valet.fix("car_city")
```
Signals: `phone_toggled`, `destination_set`, `destination_cleared`, `invitation_answered`, `purchase_made`.
