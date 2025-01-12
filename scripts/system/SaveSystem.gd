extends Node

signal run_finished(run_id)
signal new_secret_found()

enum MovementTypeEnum { MOVE_AND_ROTATE = 10, MOVE_AND_HYBRID = 15, MOVE_AND_STRAFE = 20 }

const SAVE_DIR = "user://saves/"
const SAVE_PATH = SAVE_DIR+"save.json"

const KEY_ALLOW_TELEMETRY = "telemetry"
const KEY_UUID = "uuid"
const KEY_CURRENT_LEVEL = "currentLevel"
const KEY_MAX_LEVEL_AVAILABLE = "maxLevel"
const KEY_LEVELS_INFOS_MS = "levelsInfos"
const KEY_SECRET = "secretFound"
const KEY_MOVEMENT_TYPE = "movementType"

const SAVE_VERSION = 2

var loadedData = false
var gameData : Dictionary = {}
var LevelSystem
var runInfos : RunInfos # Lazy loading

var currentLaunchUuid : String = "unset"
var runStartMs
var runTitle
var runDurationMs

var requestNode = null
var isFirstGame = false

func _ready():
	var dir = Directory.new()
	if not dir.dir_exists(SAVE_DIR):
		print("Creating SAVE directory")
		dir.make_dir(SAVE_DIR)
	LevelSystem = get_node("/root/LevelSystem")
	self.loadGameData()
	print("SaveSystem: Loaded")

func saveGameData():
	var save_file = File.new()

	save_file.open(SAVE_PATH, File.WRITE)
	save_file.store_line(JSON.print(gameData))

	save_file.close()

func loadGameData():
	var save_file = File.new()
	if not save_file.file_exists(SAVE_PATH):
		print("No game data found")
		initGameData()
		isFirstGame = true
		return

	save_file.open(SAVE_PATH, File.READ)
	gameData = JSON.parse(save_file.get_as_text()).result

	# Check if previous version
	if gameData.version == 1:
		initGameData()
		gameData[KEY_MAX_LEVEL_AVAILABLE] = LevelsList.LIST[LevelsList.LIST.size() - 1]
		gameData[KEY_CURRENT_LEVEL] = LevelsList.FROM_VERSION_1
	else :
		if not KEY_MAX_LEVEL_AVAILABLE in gameData:
			gameData[KEY_MAX_LEVEL_AVAILABLE] = ""

		if not KEY_MOVEMENT_TYPE in gameData:
			gameData[KEY_MOVEMENT_TYPE] = MovementTypeEnum.MOVE_AND_HYBRID

		if not KEY_UUID in gameData:
			_uuid_request_start()

		if not KEY_SECRET in gameData:
			gameData[KEY_SECRET] = []

		if LevelSystem.TEST_RUN != null:
			print("Test level found")
			gameData[KEY_CURRENT_LEVEL] = LevelSystem.TEST_RUN

		save_file.close()
		loadedData = true

		# Send launch infos
		if gameData[KEY_ALLOW_TELEMETRY]:
			_launch_request_start()

func initGameData(new_uuid = true):
	if LevelSystem.TEST_RUN != null:
		print("Test level found")
		gameData[KEY_CURRENT_LEVEL] = LevelSystem.TEST_RUN
	else:
		gameData[KEY_CURRENT_LEVEL] = LevelsList.LIST[0]
	gameData[KEY_LEVELS_INFOS_MS] = {}
	gameData[KEY_SECRET] = []
	gameData[KEY_MAX_LEVEL_AVAILABLE] = LevelsList.LIST[0]
	gameData[KEY_ALLOW_TELEMETRY] = true
	gameData[KEY_MOVEMENT_TYPE] = MovementTypeEnum.MOVE_AND_HYBRID
	gameData["version"] = SAVE_VERSION

	# Get an UUID
	if new_uuid:
		print_debug("Starting id request")
		_uuid_request_start()

	loadedData = true

func _uuid_request_start():
	requestNode = HTTPRequest.new()
	add_child(requestNode)
	requestNode.connect("request_completed", self, "_uuid_request_completed")
	gameData[KEY_UUID] = "tmp"
	var _error = requestNode.request(
		LevelsList.URL_TELEMETRY+ "user",
		PoolStringArray(),
		true,
		HTTPClient.METHOD_POST)

func _uuid_request_completed(_result, response_code, _headers, body):
	var uuid = body.get_string_from_utf8()
	if response_code in [200, 201]:
		print_debug("Got new id: "+uuid)
		gameData[KEY_UUID] = uuid
		saveGameData()
	_request_completed(_result, response_code, _headers, body)

func _launch_request_start():
	requestNode = HTTPRequest.new()
	add_child(requestNode)
	requestNode.connect("request_completed", self, "_launch_request_completed")

	var data = {
		"user": gameData[KEY_UUID],
		"version": SAVE_VERSION
	}

	var _error = requestNode.request(
		LevelsList.URL_TELEMETRY+ "launch",
		["Content-Type: application/json"],
		true,
		HTTPClient.METHOD_POST,
		# Data
		JSON.print(data)
	)

func _launch_request_completed(_result, response_code, _headers, body):
	var launch_uuid = body.get_string_from_utf8()
	if response_code in [200, 201]:
		currentLaunchUuid = launch_uuid
		saveGameData()
	_request_completed(_result, response_code, _headers, body)

func _run_request_start():
	requestNode = HTTPRequest.new()
	add_child(requestNode)
	requestNode.connect("request_completed", self, "_request_completed")

	var data = {
		"user": gameData[KEY_UUID],
		"launch": currentLaunchUuid,
		"version": SAVE_VERSION,
		"levelName": runInfos.id,
		"timeMs": runDurationMs
	}

	var _error = requestNode.request(
		LevelsList.URL_TELEMETRY+ "run",
		["Content-Type: application/json"],
		true,
		HTTPClient.METHOD_POST,
		JSON.print(data)
	)

func _request_completed(_result, _response_code, _headers, _body):
	remove_child(requestNode)
	requestNode = null

func _check_record():
	var runId = runInfos.id
	if not runId in gameData[KEY_LEVELS_INFOS_MS].keys() or gameData[KEY_LEVELS_INFOS_MS][runId] == null:
		gameData[KEY_LEVELS_INFOS_MS][runId] = runDurationMs
		saveGameData()
	elif runDurationMs < gameData[KEY_LEVELS_INFOS_MS][runId] :
		# New record
		gameData[KEY_LEVELS_INFOS_MS][runId] = runDurationMs
		saveGameData()

### RUN
func run_finished():
	var runId = runInfos.id
	emit_signal("run_finished", runId)
	_check_record()

	# Check if it is a new max level reached (when not demo)
	if not LevelSystem.IsDemoMode:
		var reachedIndex = LevelSystem.get_index_from_string(runId)
		var maxLevelIndex = LevelSystem.get_index_from_string(gameData[KEY_MAX_LEVEL_AVAILABLE])
		if reachedIndex > maxLevelIndex:
			gameData[KEY_MAX_LEVEL_AVAILABLE] = runId;

		# Edit current and save
		if(runInfos.hasNextRun):
			gameData[KEY_CURRENT_LEVEL] = LevelSystem.LEVELS_LIST[runInfos.index + 1]
			gameData[KEY_MAX_LEVEL_AVAILABLE] = gameData[KEY_CURRENT_LEVEL]

		saveGameData()

	# Send run infos
	if gameData[KEY_ALLOW_TELEMETRY]:
		_run_request_start()

func start_run(runId = null, secret: bool = false, is_extra := false):
	if runId != null and !is_extra:
		SaveSystem.gameData[SaveSystem.KEY_CURRENT_LEVEL] = runId

	if not loadedData:
		loadGameData()

	# If demo mode, override current
	if LevelSystem.IsDemoMode:
		runInfos = LevelSystem.get_run_infos(runId, secret, is_extra)
	else:
		runInfos = LevelSystem.get_run_infos(gameData[KEY_CURRENT_LEVEL], secret)
	runStartMs = OS.get_ticks_msec()

func level_finished():
	print_debug("Level finished")
	if runInfos.levels.size() > 0:
		runInfos.levels.pop_front()

	if runInfos.levels.size() > 0:
		# Run is not finished
		print_debug("\n######\nLoading level %s" % runInfos.levels.front())
		return load(runInfos.levels.front())

	# Run is finished
	runDurationMs = OS.get_ticks_msec() - runStartMs
	print_debug("Level finished, run (ms): %f" % [runDurationMs])
	return null

func secret_found():
	if runInfos == null:
		print_debug("Secret found without run")
		return
	runInfos.secretFound = true

	var secret_name = runInfos.id
	if not (secret_name in gameData[KEY_SECRET]):
		# New secret
		emit_signal("new_secret_found")
		gameData[KEY_SECRET].append(secret_name)
		saveGameData()
