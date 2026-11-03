
extends Node

signal job_accepted(job_id: String)
signal job_progress_updated(job_id: String, progress: int, target: int)
signal job_completed(job_id: String)

var jobs: Dictionary = {}

const RANK_MULTIPLIERS: Dictionary = {
	"D": 1.0,
	"C": 1.1,
	"B": 1.25,
	"A": 1.5,
	"S": 2.0
}


func _ready() -> void:
	load_quests()


func load_quests() -> void:
	jobs.clear()

	var directory := DirAccess.open("res://ResourcesFilesTres/quests/")

	if directory == null:
		push_error("Cannot open res://quests/")
		return

	directory.list_dir_begin()

	var file_name := directory.get_next()

	while file_name != "":
		if not directory.current_is_dir() and file_name.ends_with(".tres"):
			var resource_path := "res://ResourcesFilesTres/quests/" + file_name
			var resource: Resource = load(resource_path)

			if resource is QuestData:
				var quest := resource as QuestData

				if quest.quest_id.is_empty():
					push_warning("Quest has no ID: " + resource_path)
				elif jobs.has(quest.quest_id):
					push_warning("Duplicate quest ID: " + quest.quest_id)
				else:
					jobs[quest.quest_id] = quest

		file_name = directory.get_next()

	directory.list_dir_end()

	print("Loaded ", jobs.size(), " quest resources.")


## Credits paid by the most recently completed job (after the reputation modifier).
var last_payout: int = 0


## Credits a job pays right now: lower reputation reduces pay (design doc, City Combat Rules).
func job_pay(job_id: String) -> int:
	var job: QuestData = get_quest(job_id)
	if job == null:
		return 0
	var rep_factor := 0.6 + 0.4 * (float(Globalvar.current_reputation) / 100.0)
	return int(round(job.pay * rep_factor))


## Job ids that can be accepted right now (not active, not completed).
func available_jobs() -> Array[String]:
	var out: Array[String] = []
	var ids: Array = jobs.keys()
	ids.sort()
	for id in ids:
		if not Globalvar.completed_jobs.has(id) and Globalvar.active_job_id != id:
			out.append(id)
	return out


func cancel_job() -> void:
	if Globalvar.active_job_id == "":
		return
	var job_id: String = Globalvar.active_job_id
	Globalvar.active_job_id = ""
	Globalvar.active_job_title = ""
	Globalvar.active_job_description = ""
	Globalvar.active_job_progress = 0
	Globalvar.active_job_target = 0
	job_progress_updated.emit(job_id, 0, 0)


func get_quest(job_id: String) -> QuestData:
	return jobs.get(job_id) as QuestData


func get_rank_multiplier() -> float:
	return float(
		RANK_MULTIPLIERS.get(Globalvar.current_rank, 1.0)
	)


func get_next_available_quest_id() -> String:
	if Globalvar.active_job_id != "":
		return ""

	var quest_ids: Array = jobs.keys()
	quest_ids.sort()

	for job_id in quest_ids:
		if not Globalvar.completed_jobs.has(job_id):
			return job_id

	return ""


func get_job_status(job_id: String) -> String:
	if not jobs.has(job_id):
		return "Unknown"

	if Globalvar.completed_jobs.has(job_id):
		return "Completed"

	if Globalvar.active_job_id == job_id:
		return "Active"

	if Globalvar.active_job_id != "":
		return "Blocked"

	return "Available"


func can_accept_job(job_id: String) -> bool:
	if not jobs.has(job_id):
		return false

	if Globalvar.active_job_id != "":
		return false

	if Globalvar.completed_jobs.has(job_id):
		return false

	return true


func accept_job(job_id: String) -> bool:
	if not can_accept_job(job_id):
		return false

	var job: QuestData = get_quest(job_id)

	if job == null:
		return false

	Globalvar.active_job_id = job.quest_id
	Globalvar.active_job_title = job.title
	Globalvar.active_job_description = job.description
	Globalvar.active_job_progress = 0
	Globalvar.active_job_target = maxi(1, job.target)

	job_accepted.emit(job_id)
	job_progress_updated.emit(
		job_id,
		Globalvar.active_job_progress,
		Globalvar.active_job_target
	)

	return true


func add_job_progress(amount: int = 1) -> void:
	if Globalvar.active_job_id.is_empty():
		return

	if amount <= 0:
		return

	var job_id: String = Globalvar.active_job_id

	Globalvar.active_job_progress = mini(
		Globalvar.active_job_progress + amount,
		Globalvar.active_job_target
	)

	job_progress_updated.emit(
		job_id,
		Globalvar.active_job_progress,
		Globalvar.active_job_target
	)

	if Globalvar.active_job_progress >= Globalvar.active_job_target:
		complete_job(job_id)


func complete_job(job_id: String) -> bool:
	if Globalvar.active_job_id != job_id:
		return false

	var job: QuestData = get_quest(job_id)

	if job == null:
		push_error("Cannot complete missing quest: " + job_id)
		return false

	# Use the rank the player has when the job is completed.
	var multiplier: float = get_rank_multiplier()

	var earned_renown: int = roundi(
		job.renown_reward * multiplier
	)

	var earned_points: int = roundi(
		job.credits_reward * multiplier
	)

	RankManager.add_renown(
		earned_renown,
		"City Job: " + job.title
	)

	Globalvar.current_points += earned_points
	last_payout = job_pay(job_id)
	Globalvar.add_credits(last_payout)
	Globalvar.change_reputation(1)

	if not Globalvar.completed_jobs.has(job_id):
		Globalvar.completed_jobs.append(job_id)

	Globalvar.active_job_id = ""
	Globalvar.active_job_title = ""
	Globalvar.active_job_description = ""
	Globalvar.active_job_progress = 0
	Globalvar.active_job_target = 0

	job_completed.emit(job_id)

	print(
		"Completed: ", job.title,
		" | Rank: ", Globalvar.current_rank,
		" | Multiplier: x", multiplier,
		" | Renown earned: +", earned_renown,
		" | Credits earned: +", earned_points
	)

	return true


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("tb") and not event.is_echo():
		add_job_progress(1)
