package game

import "core:fmt"
import "core:math"
import "core:math/linalg"
import "core:strings"
import hm "handle_map_static"
import maps "mapgen"
import rl "vendor:raylib"

//boilerplate / starter code for your game-specific logic in this engine
GAME_NAME :: "compressiform"
UI_MAIN_FONT_SIZE :: 72
UI_SECONDARY_FONT_SIZE :: 42
IN_GAME_FONT_SIZE :: 50
BACKGROUND_MAP_COLOR :: rl.Color{128, 128, 128, 255}
CAMERA_MAP_COLOR :: rl.Color{99, 155, 255, 255}
EDGE_SCROLL_MARGIN :: 150 // pixels from window edge that triggers scrolling
CAMERA_BOUNDS_PADDING :: vec2{TILE_SIZE * 1.5, TILE_SIZE * .5} // extra world-space margin so walls stay visible
EDGE_SCROLL_ENABLED :: true
STACK_START_COLOR :: rl.Color{255, 195, 59, 255}
SLATE_GRAY :: rl.Color{210, 210, 220, 255}
MENU_SCREEN_DIMS :: vec2{WINDOW_WIDTH, WINDOW_HEIGHT}
LETTERS_PER_LINE :: 30
LINES_PER_TABLET :: 10
TABLET_THUD_SCREENSHAKE_AMT :: 20
SCREENSHAKE_DECAY :: 18
@(rodata)
LEVELS := []Level {
	{
		target_message = "Made for Ludum Dare 59 by Nathaniel Saxe and Ryan Kann. -_-_-_-_-_-_-_-_-_-_-_-_-_-_ -_-_-_-_-_-_-_-_-_-_-_-_-_-_ -_-_-_-_-_-_-_-_-_-_-_-_-_-_ -_-_-_-_-_-_-_-_-_-_-_-_-_-_ -_-_-_-_-_-_-_-_-_-_-_-_-_-_ -_-_-_-_-_-_-_-_-_-_-_-_-_-_ -_-_-_-_-_-_-_-_-_-_-_-_-_-_ -_-_-_-_-_-_-_-_-_-_-_-_-_-_ -_-_-_-_-_-_-_-_-_-_-_-_-_-_ In a world where they never figured out paper, important messages are sent overseas on stone tablets like these. You are in charge of compressing longer messages until they can fit on a single boat, saving your shipping company millions each year. Speaking of which, this boat can only fit 2 stone tablets, so you'll have to figure out a way to make the message a bit smaller. Looks like '-_-_-_-_-_-_-_-_-_-_-_-_-_-_' is repeated a bunch of times in a row on the first tablet, maybe you can use a number as a shorthand for how many times that part of the message was repeated.",
		max_tablets = 3,
		time_limit = 180,
	},
	{
		target_message = "Made for Ludum Dare 59 by Nathaniel Saxe and Ryan Kann. -_-_-_-_-_-_-_-_-_-_-_-_-_-_ -_-_-_-_-_-_-_-_-_-_-_-_-_-_ -_-_-_-_-_-_-_-_-_-_-_-_-_-_ -_-_-_-_-_-_-_-_-_-_-_-_-_-_ -_-_-_-_-_-_-_-_-_-_-_-_-_-_ -_-_-_-_-_-_-_-_-_-_-_-_-_-_ -_-_-_-_-_-_-_-_-_-_-_-_-_-_ -_-_-_-_-_-_-_-_-_-_-_-_-_-_ -_-_-_-_-_-_-_-_-_-_-_-_-_-_ Many copies of the same word in a row is unusual, though. We'll have to think of another trick. We've got all these pebbles lying around the warehouse. Maybe we can attach them to the tablet, along with instructions saying that whenever you see a white pebble, you should replace it with a particular word. You can use an equals sign to say '(white pebble) = the' and then replace all the ' the ' in this message with white pebbles.",
		max_tablets = 3,
		time_limit = 120,
	},
	{
		target_message = "Made for Ludum Dare 59 by Nathaniel Saxe and Ryan Kann. -_-_-_-_-_-_-_-_-_-_-_-_-_-_ -_-_-_-_-_-_-_-_-_-_-_-_-_-_ -_-_-_-_-_-_-_-_-_-_-_-_-_-_ -_-_-_-_-_-_-_-_-_-_-_-_-_-_ -_-_-_-_-_-_-_-_-_-_-_-_-_-_ -_-_-_-_-_-_-_-_-_-_-_-_-_-_ -_-_-_-_-_-_-_-_-_-_-_-_-_-_ -_-_-_-_-_-_-_-_-_-_-_-_-_-_ -_-_-_-_-_-_-_-_-_-_-_-_-_-_ Ok let's be real, the person on the other end of the message probably doesn't need to know exactly how many of those dashes there were. The message still *means* about the same thing regardless. See if it still works if you just remove them entirely, as long as the actual meaning of the message is preserved I'm sure it will be understood.",
		max_tablets = 2,
		time_limit = 120,
	},
}

//object tags
//these are mostly game-specific boolean tags on objects
//GameObjects can have any set of these tags, encoded using a bit_set[ObjectTag] called `tags`
//bit_set is encoded in a 128-bit value, so the max number of tags is 128
ObjectTag :: enum {
	//engine-required tags
	Collide, // if present, the collision system will consider this object in collisions
	Sprite, // if present, the renderer will draw the sprite / texture data of this object
	Text, // if present, the renderer will draw the text data of this object
	DoNotSerialize,
	DontDestroyOnLoad,
	CustomDraw,
	//user-defined tags
	Draggable,
	Fall,
}

SpawnType :: enum {
	None,
	Camera,
	Stack,
	Background,
}

Level :: struct {
	time_limit:     f64,
	target_message: string,
	minimum_loss:   f64,
	max_tablets:    int,
}
LevelProgress :: struct {
	level:          Level,
	message:        Message,
	time_remaining: f64,
}
Word :: struct {
	str:         string,
	letter_size: f64,
}
Number :: struct {
	number: int, //should be 0-9
}
//used for find/replace
Equals :: distinct struct{}
//used for counting occurrences of stuff
Times :: distinct struct{}
MessageObjectType :: enum {
	Egg,
	SmashedEgg,
	Chick,
	Apple,
	RottenApple,
	Orange,
	RottenOrange,
	Pebble,
}
//some other random object that is stuck on the tablet
MessageObject :: distinct struct {
	type:                MessageObjectType,
	get_message_content: proc() -> string,
}
MessageElementContent :: union {
	Word,
	Number,
	Equals,
	MessageObject,
}
MessageElementPosition :: struct {
	tablet, line: int,
	pos:          f64,
}
MessageElement :: struct {
	content:        MessageElementContent,
	using position: MessageElementPosition,
}
Message :: [dynamic]MessageElement

GameSpecificProps :: struct {
	text:                string,
	get_message_element: proc() -> MessageElement,
}

ChunkLoadingMode :: enum {
	Room,
	Proximity,
}
GameSpecificGlobalState :: struct {
	clicked_ui_object:    Maybe(GameObjectHandle),
	dragged_object:       Maybe(GameObjectHandle),
	level_number:         int,
	using level_progress: LevelProgress,
	stage:                GameStage,
	menu_container:       GameObjectHandle,
	global_tilemap:       Tilemap `cbor:"-"`, //not serialized - too big
	chunk_loading_mode:   ChunkLoadingMode,
	//we load the map immediately, but need to remember
	//where to spawn the player when the player object is spawned later
	camera_spawn_point:   vec2,
	camera_bounds:        Rect,
	screen_shake_amt:     f64,
	screen_shake:         vec2,
	tablet_stack_bottom:  vec2,
	color_to_tiletype:    map[rl.Color]TileType,
	color_to_spawn:       map[rl.Color]SpawnType,
}

GameSpecificFrameState :: struct {
	mouse_screen_pos, mouse_world_pos: vec2,
}


//object variants
//in contrast to tags, each object has exactly one variant
//GameObject has a field called `variant` which is this GameObjectVariant union type
//this is intended for mutually exclusive types of objects which need their own state fields
//for example, an enemy might need a max speed, state machine behavior, and an equipped weapon
//but those things will never apply to a collectible item
//so Enemy and Collectible can be two variants in the union
DefaultVariant :: distinct struct{}
ButtonCallbackInfo :: struct {
	game:          ^Game,
	button:        GameObjectInst(UIButton),
	button_handle: GameObjectHandle,
}
UIButton :: struct {
	min_scale, max_scale: vec2,
	on_click_start:       proc(info: ButtonCallbackInfo) `cbor:"-"`, //triggered when mouse button down and hovering button
	on_click:             proc(info: ButtonCallbackInfo) `cbor:"-"`, //triggered when mouse button up and hovering button - most of the time this is what you want
}
Tablet :: struct {
	index_within_message: int,
}
GameObjectVariant :: union {
	DefaultVariant,
	Tablet,
	UIButton,
}

//type constraints to check at runtime (outside of Odin's type system)
//these will be checked once per frame and print nice errors if violated
//checks are not very expensive but can be turned off with a flag for release builds
//for example, you might want to assert that no object ever has both of a pair of tags
//or that no objects with the DecorativeSprite variant are missing the Sprite tag
TYPE_ASSERTS := []GameObjectTypeAssert{}

//collision layers
//you may want some categories of objects to only collide with certain other categories
//instead of you providing logic inside each collision event to specifically ignore the ones you want,
//it's simpler and faster to have the collision detection logic not even generate the collision event
//to that end, you can define categories of objects which the collision system knows about
CollisionLayer :: enum {
	Default = 0,
	Wall, // tilemaps are a special case in this engine
}
//which collision layers can hit which others?
@(rodata)
COLLISION_MATRIX: [CollisionLayer]bit_set[CollisionLayer] = #partial {
	.Default = ~{}, //by default, collide with all layers
}

//named render layers
//a render layer is really just an index into an array of object handles
//determining the order in which the game draws things
//lower indices are drawn first and so end up at the bottom
//to keep things consistent, I find it helpful to name some of these layers with what they represent in the game world
RenderLayer :: enum uint {
	Bottom  = 0,
	Floor   = NUM_RENDER_LAYERS * 50.0 / 256,
	Enemy   = NUM_RENDER_LAYERS * 100.0 / 256,
	Bullet  = NUM_RENDER_LAYERS * 120.0 / 256,
	Player  = NUM_RENDER_LAYERS * 128.0 / 256,
	Ceiling = NUM_RENDER_LAYERS * 200.0 / 256,
	UI      = NUM_RENDER_LAYERS * 240.0 / 256,
	Top     = NUM_RENDER_LAYERS - 1,
}

//tilemap tiles are distinct from regular GameObjects in this engine
//this is because they are by far the most common type of object in practice
//so benefit more from some optimizations and simplifying assumptions
//unlike GameObjects, tiles in the tilemap
//1) are always static - they do not move, and collisions with them have
//2) are always located at a particular grid cell in the tilemap
//3) are identical to all other tiles of the same type
//   there is no tile-specific data at a particular spot in the grid
//   all that is stored is the tile type id
//types of tiles
TileType :: enum {
	None,
	Wall,
}
//properties of each type of tile
TILE_PROPERTIES := [TileType]TileTypeInfo {
	.None = {
		texture = atlas_textures[.None],
		render_layer = uint(RenderLayer.Floor),
		random_rotation = true,
	},
	.Wall = {
		collision = {layer = .Wall, resolve = true, trigger_events = true},
		texture = atlas_textures[.Wood4],
		render_layer = uint(RenderLayer.Floor),
	},
}

//this keeps track of whether you are in the menu or in the game
GameStage :: enum {
	Init,
	Started,
	Compressing,
	Scoring,
	GameOver,
}

//game-specific initialization logic (run once when game is started)
//typically this will be "set up the main menu"
game_start :: proc(game: ^Game) {
	// NLP smoke test — remove after verifying
	print("=== NLP similarity tests ===")
	print("identical:", compute_similarity("hello world", "hello world"))
	print("subset:", compute_similarity("the quick brown fox jumps", "quick fox"))
	print("no overlap:", compute_similarity("hello world", "goodbye moon"))
	print("case insensitive:", compute_similarity("Hello World", "hello world"))
	print("empty vs text:", compute_similarity("", "hello"))
	print("reordered:", compute_similarity("stone tablet message", "message stone tablet"))
	print("--- tricky cases ---")
	print("synonym (big/large):", compute_similarity("the big house", "the large house"))
	print("synonym (fast/quick):", compute_similarity("the fast runner", "the quick runner"))
	print(
		"abbreviation:",
		compute_similarity("compressing messages on tablets", "compress msgs on tabs"),
	)
	print(
		"dropped filler:",
		compute_similarity("I am going to the store to buy some food", "going store buy food"),
	)
	print(
		"paraphrase:",
		compute_similarity("the cat sat on the mat", "a feline rested on the rug"),
	)
	print("repetition padding:", compute_similarity("hello", "hello hello hello hello"))
	print(
		"actual level msg:",
		compute_similarity(
			"In a world where they never figured out paper, important messages are still sent overseas on stone tablets",
			"important messages sent overseas on stone tablets",
		),
	)
	print("--- hard paraphrases ---")
	print(
		"clothing/boutique:",
		compute_similarity(
			"Sally went to the clothing store.",
			"Sally popped on over to the boutique.",
		),
	)
	print("negation:", compute_similarity("I love this movie", "I hate this movie"))
	print(
		"passive voice:",
		compute_similarity("The dog chased the cat", "The cat was chased by the dog"),
	)
	print(
		"totally unrelated:",
		compute_similarity("The stock market crashed yesterday", "She baked a chocolate cake"),
	)
	print("============================")

	game.color_to_tiletype[rl.BLACK] = .Wall
	game.color_to_tiletype[STACK_START_COLOR] = .Wall
	game.color_to_tiletype[BACKGROUND_MAP_COLOR] = .None
	game.color_to_spawn[CAMERA_MAP_COLOR] = .Camera
	game.color_to_spawn[STACK_START_COLOR] = .Stack
	load_map :: proc() -> (tilemap: Tilemap, camera_spawn, stack_start: TilemapTileId) {
		MAP_DATA :: #load("map.png")
		tiles_img := rl.LoadImageFromMemory(".png", raw_data(MAP_DATA), i32(len(MAP_DATA)))
		tiles_buf := maps.img_to_buf(tiles_img, transpose = true)
		get_tile :: proc(c: rl.Color) -> Tile {
			t := Tile{}
			tiletype, ok := game.color_to_tiletype[c]
			if ok {
				t.type = tiletype
			}
			spawntype, spawn_ok := game.color_to_spawn[c]
			if spawn_ok {
				t.spawn = spawntype
			}
			return t
		}
		return img_to_tilemap(tiles_buf, get_tile)
	}
	cam_spawn_tile, stack_start_tile: TilemapTileId
	game.global_tilemap, cam_spawn_tile, stack_start_tile = load_map()
	game.camera_spawn_point = get_tile_center(cam_spawn_tile)
	game.tablet_stack_bottom = get_tile_center(stack_start_tile) - {0, TILE_SIZE / 2}
	game.main_camera.position = game.camera_spawn_point
	game.camera_bounds = compute_camera_bounds(game.global_tilemap)
	//TODO spawn background
	spawn_object(
		{
			name = "background",
			parent_handle = game.screen_space_parent_handle,
			scale = {200, 200},
			texture = atlas_textures[.Darkrock],
			render_layer = uint(RenderLayer.Bottom),
		},
	)
	spawn_button(MENU_SCREEN_DIMS * {0.5, 0.5}, .White, "Start", proc(info: ButtonCallbackInfo) {
		game.stage = .Started
		if ODIN_OS == .JS && !rl.IsAudioDeviceReady() {
			rl.InitAudioDevice()
		}
		hm.remove(&game.objects, info.button.handle)
	})
	game.stage = .Init
}

//game-specific teardown / reset logic
reset_game :: proc(g: ^Game = game) {
	hm.clear(&g.objects)
	clear(&g.chunks)
	clear(&g.loaded_chunks)
	recreate_final_transforms(g)
	g.frame_counter = 0
	g.screen_space_parent_handle = spawn_object(GameObject{name = "screen space parent"})
}

//game-specific update logic (run once per frame)
game_update :: proc(game: ^Game, dt: f64) {
	timer := timer()
	game.mouse_screen_pos = linalg.to_f64(rl.GetMousePosition())
	game.mouse_world_pos = screen_to_world(linalg.to_f64(rl.GetMousePosition()), screen_conversion)
	handle_ui_buttons()
	switch game.stage {
	case .Init:
	case .Started:
		game.level = LEVELS[game.level_number]
		level_start(game.level)
		rl.PlaySound(get_sound("tablet-whoosh.wav"))
		game.stage = .Compressing
	case .Compressing:
		if game.frame_counter % 2 == 0 {
			game.screen_shake = random_point_in_circle({0, 0}, game.screen_shake_amt)
		}
		game.screen_shake_amt = max(0, game.screen_shake_amt - SCREENSHAKE_DECAY * dt)
		camera_dir := vec2{0, 0}
		when EDGE_SCROLL_ENABLED {camera_dir += edge_scroll()}
		game.main_camera.position += 1000 * dt * camera_dir
		clamp_camera_to_bounds(&game.main_camera.position, game.camera_bounds)
		//do gravity
		{it := hm.make_iter(&game.objects)
			for obj in all_objects_with_tags(&it, .Fall) {
				GRAVITY_STRENGTH :: 800
				obj.acceleration.y += GRAVITY_STRENGTH
			}
		}
		dragged, dragging := game.dragged_object.?
		if dragging {
			dragged_obj := get_object(dragged)
			mouse_world_diff := game.mouse_world_pos - game.prev_frame.mouse_world_pos
			dragged_obj.position += mouse_world_diff
			if rl.IsMouseButtonReleased(.LEFT) {
				drag_stop()
			}
		} else {
			draggable_objects := get_draggables_at_cursor(game.mouse_world_pos)
			click_started := len(draggable_objects) > 0 && rl.IsMouseButtonPressed(.LEFT)
			if click_started {
				drag_start(draggable_objects[0])
			}
		}
		{it := hm.make_iter(&game.objects)
			for tablet, h in all_objects_with_variant(&it, Tablet) {
				collisions := game.collisions[h]
				for collision in collisions {
					if collision.type != .start {continue}
					switch other in collision.b {
					case GameObjectHandle: //don't care
					case TilemapTileId:
						//hit the ground
						rl.PlaySound(get_sound("tablet-thud-1.wav"))
						rl.PlaySound(get_sound("tablet-thud-2.wav"))
						game.screen_shake_amt = TABLET_THUD_SCREENSHAKE_AMT
						it_children := hm.make_iter(&game.objects)
						//unparent children so they aren't in local coords anymore
						for child in hm.iter(&it) {
							if child.parent_handle != h {continue}
							world_pos := local_to_world(h, child.position + tablet.pivot)
							child.position = world_pos
							child.parent_handle = nil
							child.tags += {.Draggable}
						}
					}
				}
			}
		}
	// print(mouse_pos, mouse_tile)

	//update timer
	//if time is up, end the level
	//handle click & drag
	//on drag stop, update the level message
	case .Scoring:
		//progress through scoring animation
		game.level_number += 1
	case .GameOver:
	//show new game button
	}
	get_axis :: proc(key_neg, key_pos: rl.KeyboardKey) -> f64 {
		return f64(int(rl.IsKeyDown(key_pos))) - f64(int(rl.IsKeyDown(key_neg)))
	}
	WASD :: proc() -> vec2 {
		return {get_axis(.A, .D), get_axis(.W, .S)}
	}
	edge_scroll :: proc() -> vec2 {
		mouse := linalg.to_f64(rl.GetMousePosition())
		screen := vec2{f64(rl.GetScreenWidth()), f64(rl.GetScreenHeight())}
		dir := vec2{0, 0}
		if mouse.x < EDGE_SCROLL_MARGIN {dir.x = -1}
		if mouse.x > screen.x - EDGE_SCROLL_MARGIN {dir.x = 1}
		if mouse.y < EDGE_SCROLL_MARGIN {dir.y = -1}
		if mouse.y > screen.y - EDGE_SCROLL_MARGIN {dir.y = 1}
		return dir
	}

	clamp_camera_to_bounds :: proc(cam_pos: ^vec2, bounds: Rect) {
		half_screen := vec2{f64(rl.GetScreenWidth()), f64(rl.GetScreenHeight())} / 2
		cam_min := vec2{bounds.x, bounds.y} + half_screen - CAMERA_BOUNDS_PADDING
		cam_max :=
			vec2{bounds.x + bounds.width, bounds.y + bounds.height} -
			half_screen +
			CAMERA_BOUNDS_PADDING
		// if bounds are smaller than screen, center the camera
		if cam_min.x >
		   cam_max.x {cam_pos.x = (cam_min.x + cam_max.x) / 2} else {cam_pos.x = clamp(cam_pos.x, cam_min.x, cam_max.x)}
		if cam_min.y >
		   cam_max.y {cam_pos.y = (cam_min.y + cam_max.y) / 2} else {cam_pos.y = clamp(cam_pos.y, cam_min.y, cam_max.y)}
	}
}

compute_camera_bounds :: proc(tilemap: Tilemap) -> Rect {
	min_x, min_y := max(int), max(int)
	max_x, max_y := min(int), min(int)
	for r in 0 ..< len(tilemap) {
		for c in 0 ..< len(tilemap[r]) {
			if tilemap[r][c].type != .Wall {
				min_x = min(min_x, r)
				min_y = min(min_y, c)
				max_x = max(max_x, r)
				max_y = max(max_y, c)
			}
		}
	}
	return {
		x = f64(min_x) * TILE_SIZE,
		y = f64(min_y) * TILE_SIZE,
		width = f64(max_x - min_x + 1) * TILE_SIZE,
		height = f64(max_y - min_y + 1) * TILE_SIZE,
	}
}

game_specific_load :: proc(game: ^Game = game, save: ^GameSave) {
	//intentionally left blank
	//save / load not supported for target build which is web build
}

//decode message
message_to_string :: proc(message: Message) -> string {
	replacements := map[MessageElement]MessageElement{}
	result := ""
	//parse message into result
	i := 0
	for i < len(message) {
		element := message[i]
		//assume we are at the start of a token
		//a token is either
		//  a single element
		//  [key: MessageElement] equals [value]
		//  [number] times [value]
		switch content in element.content {
		case Number:
			repetitions := content.number
			sb := strings.builder_make(); defer strings.builder_destroy(&sb)
			for i < len(message) {
				i += 1
				next_element := message[i]
				switch next_content in next_element.content {
				case Number:
					repetitions *= 10
					repetitions += next_content.number
				case Word:
					for _ in 0 ..< repetitions {
						fmt.sbprint(&sb, next_content.str)
					}
				case Equals:
				//invalid
				case MessageObject:
				//
				}
			}
		case Equals:
		//should be unreachable if message is valid - if invalid, do nothing
		case MessageObject:
			if i < len(message) - 2 {
				next_element := message[i + 1]
				#partial switch next_content in next_element.content {
				case Equals:
				// handle_equals(message, i)
				case:
					break
				}
			}
		case Word:
			if i < len(message) - 2 {
				next_element := message[i + 1]
				#partial switch next_content in next_element.content {
				case Equals:
				// handle_equals(message, i)
				case:
					break
				}
			}
		}
	}
	return result
}

get_message_element_text :: proc(element: MessageElementContent) -> string {
	text: string
	switch content in element {
	case Word:
		text = content.str
	case Number:
		text = fmt.aprint(content.number)
	case Equals:
		text = "="
	case MessageObject:
		text = "."
	}
	return text
}

get_message_element_size :: proc(element: MessageElementContent) -> vec2 {
	text := get_message_element_text(element)
	letter_size: f64 = 1 //TODO this probably won't end up being implemented
	font_size := f32(letter_size * IN_GAME_FONT_SIZE)
	world_size_pix := rl.MeasureTextEx(
		global_default_font,
		strings.clone_to_cstring(text),
		font_size,
		0,
	)
	return vec2f32_to_vec2(world_size_pix)
}

//figure out the line, column and tablet number of all the things in the message
//basically just laying out text into pages
set_message_element_positions :: proc(
	message: ^Message,
	letters_per_line, lines_per_tablet: int,
) -> (
	num_tablets_needed: int,
) {
	AVG_PIXELS_PER_LETTER: f64 : 22 //measured
	WORD_SPACING_PIXELS: f64 : 20
	tablet := 0
	line := 0
	column: f64 = 0
	sum_ratios: f64 = 0
	num_ratios: f64 = 0
	for &element in message {
		elem_size := get_message_element_size(element.content)
		elem_len := elem_size.x
		elem_len_with_space := elem_len + WORD_SPACING_PIXELS
		text := get_message_element_text(element.content)
		sum_ratios += elem_len / f64(len(text))
		num_ratios += 1
		column += elem_len_with_space
		//fix run off end of line
		if column - WORD_SPACING_PIXELS > f64(letters_per_line) * AVG_PIXELS_PER_LETTER {
			column = elem_len_with_space
			line += 1
		}
		//fix run off end of tablet
		if line > lines_per_tablet {
			line = 0
			tablet += 1
		}
		element.position = {tablet, line, column - elem_len_with_space}
	}
	print("alskjdasd", sum_ratios / num_ratios)
	return tablet + 1
}
//make message from string
string_to_message :: proc(s: string) -> Message {
	result := Message{}
	words := strings.split(s, " ")
	for word in words {
		if word != "" {
			append(&result, MessageElement{content = Word{str = word, letter_size = 1}})
		}
	}
	return result
}

get_draggables_at_cursor :: proc(cursor_pos: vec2) -> []GameObjectHandle {
	result := [dynamic]GameObjectHandle{}
	it := hm.make_iter(&game.objects)
	for obj, h in all_objects_with_tags(&it, .Draggable) {
		world_box := get_bounding_box_for_moving_shape(
			get_moving_hitbox_for_object(obj, game.final_transforms[h.idx].transform, 0).moving_shape,
		)
		if is_point_in_aabb(cursor_pos, world_box) {
			append(&result, h)
		}
	}
	return result[:]
}

drag_start :: proc(h: GameObjectHandle) {
	game.dragged_object = h
	obj := get_object(h)
}

drag_stop :: proc() {
	dragged, dragging := game.dragged_object.?
	if !dragging {return}
	dragged_obj := get_object(dragged)
	game.dragged_object = nil
	tablet, over_tablet := get_containing_tablet(game.mouse_world_pos).?
	if !over_tablet {return}
	tablet_rect := aabb_to_rect(tablet.hitbox.shape.(AABB))
	elem_pos := world_to_tablet(tablet, game.mouse_world_pos)
	// message_idx := closest_message_idx_before(elem_pos, game.message)


	get_containing_tablet :: proc(world_pos: vec2) -> Maybe(GameObjectInst(Tablet)) {
		it := hm.make_iter(&game.objects)
		for obj, h in all_objects_with_variant(&it, Tablet) {
			world_box := get_bounding_box_for_moving_shape(
				get_moving_hitbox_for_object(obj, game.final_transforms[h.idx].transform, 0).moving_shape,
			)
			if is_point_in_aabb(world_pos, world_box) {
				return obj
			}
		}
		return nil //not over any tablet
	}

}
print_message :: proc(m: ^Message) {
	for element in m {
		print(
			element.content,
			"is at position",
			element.pos,
			"on line",
			element.line,
			"on tablet",
			element.tablet,
		)
	}
}

//called once at start of game
//called at start of level
spawn_tablets :: proc(level: Level, message: ^Message) {
	//divide message into tablet-sized chunks
	num_tablets := set_message_element_positions(message, LETTERS_PER_LINE, LINES_PER_TABLET)
	// print_message(message)
	//for each chunk, spawn tablet displaying that message
	tablet_objects := [dynamic]GameObjectHandle{}
	for i in 0 ..< num_tablets {
		tablet_start_height :: 1500
		tablet_offset: vec2 : {1200, -800}
		spawn_tablet(
			game.tablet_stack_bottom -
			{tablet_offset.x, tablet_start_height} +
			f64(i) * tablet_offset,
			message,
			i,
		)
	}
}
//called from spawn_tablets
spawn_tablet :: proc(pos: vec2, message: ^Message, tablet_number: int) -> GameObjectHandle {
	//shoot bullet
	tex := atlas_textures[.Tablet]
	tex_dims := vec2{tex.rect.width, tex.rect.height}
	scale := vec2{1, 1}
	tablet_def := GameObject {
		name = fmt.aprint("tablet", tablet_number),
		transform = {position = pos, scale = scale, pivot = {tex_dims.x / 2, tex_dims.y / 2}},
		render_info = {
			texture = tex,
			color = rl.WHITE,
			render_layer = uint(RenderLayer.Floor),
			keep_original_dimensions = true,
		},
		velocity = {0, 100}, //throw it down
		hitbox = {layer = .Default, shape = AABB{min = (-tex_dims / 2), max = tex_dims / 2}},
		tags = {.Sprite, .Collide, .Fall},
		variant = Tablet{tablet_number},
	}
	tablet_handle := spawn_object(tablet_def)
	tablet := get_object(tablet_handle, Tablet)
	for element in message {
		if element.tablet != tablet_number {continue}
		spawn_message_element_object(element, tablet)
	}
	return tablet_handle

	spawn_message_element_object :: proc(
		element: MessageElement,
		tablet: GameObjectInst(Tablet),
	) -> GameObjectHandle {
		text := get_message_element_text(element.content)
		letter_size: f64 = 1 //TODO this probably won't end up being implemented
		font_size := f32(letter_size * IN_GAME_FONT_SIZE)
		size := get_message_element_size(element.content)
		hitbox_offset := vec2{0, size.y / 2}
		obj_def := GameObject {
			name = text,
			position = tablet_to_world(tablet, element.position),
			scale = {1, 1},
			pivot = {0, 0},
			parent_handle = tablet.handle,
			render_info = {
				render_layer = uint(RenderLayer.Ceiling),
				texture = atlas_textures[.None],
				text_render_info = {
					text_color = SLATE_GRAY,
					font_size = font_size,
					text_alignment = .Left,
				},
			},
			hitbox = {shape = AABB{vec2{0, 0} - hitbox_offset, size - hitbox_offset}},
			tags = {.Text, .Collide},
			text = text,
		}
		return spawn_object(obj_def)
	}
}


tablet_to_local :: proc(tablet: GameObjectInst(Tablet), elem: MessageElementPosition) -> vec2 {
	tablet_rect := aabb_to_rect(tablet.hitbox.shape.(AABB))
	line_width := tablet_rect.width * 0.8
	line_height := (tablet_rect.height * 0.6) / LINES_PER_TABLET
	top_corner_of_content := 0.1 * vec2{tablet_rect.width, tablet_rect.height} - {475, 300}
	return top_corner_of_content + {elem.pos, line_height * f64(elem.line)}
}
tablet_to_world :: proc(tablet: GameObjectInst(Tablet), elem: MessageElementPosition) -> vec2 {
	return local_to_world(tablet.handle, tablet_to_local(tablet, elem))
}

local_to_tablet :: proc(
	tablet: GameObjectInst(Tablet),
	local_pos: vec2,
) -> MessageElementPosition {
	tablet_rect := aabb_to_rect(tablet.hitbox.shape.(AABB))
	line_width := tablet_rect.width * 0.8
	line_height := (tablet_rect.height * 0.6) / LINES_PER_TABLET
	top_corner_of_content := 0.1 * vec2{tablet_rect.width, tablet_rect.height} - {475, 300}
	pos := local_pos.x - top_corner_of_content.x
	line := math.round((local_pos.y))
	return {}
}

world_to_tablet :: proc(
	tablet: GameObjectInst(Tablet),
	world_pos: vec2,
) -> MessageElementPosition {
	return local_to_tablet(tablet, world_to_local(tablet.handle, world_pos))
}


level_start :: proc(level: Level) {
	message := string_to_message(level.target_message)
	spawn_tablets(level, &message)
}
level_end :: proc(level: Level) {}
level_score :: proc(level: Level) -> f64 {
	compressed := message_to_string(game.message)
	return compute_similarity(level.target_message, compressed)
}
// end_current_level :: proc() {}

spawn_button :: proc(
	pos: vec2,
	texture: TextureName, //TODO probably need to eventually supply hover / click animations
	text: string,
	on_click: proc(info: ButtonCallbackInfo),
) -> GameObjectHandle {
	tex := atlas_textures[texture]
	min_scale :: vec2{3, 0.9}
	button_obj := GameObject {
		name = fmt.aprint(text, "button"),
		text = text,
		transform = {
			position = pos,
			rotation = 0,
			scale = min_scale,
			pivot = vec2{tex.rect.width, tex.rect.height} / 2,
		},
		render_info = {
			texture = tex,
			color = rl.DARKGRAY,
			render_layer = uint(RenderLayer.UI),
			text_render_info = {font_size = UI_MAIN_FONT_SIZE, text_color = SLATE_GRAY},
		},
		tags = {.Sprite, .Text, .DoNotSerialize, .DontDestroyOnLoad},
		variant = UIButton {
			min_scale = min_scale,
			max_scale = {min_scale.x * 1.3, min_scale.y * 1.3},
			on_click = on_click,
		},
		parent_handle = game.screen_space_parent_handle,
	}
	return spawn_object(button_obj)
}

handle_ui_buttons :: proc() {
	mouse_screen_pos := linalg.to_f64(rl.GetMousePosition())
	it := hm.make_iter(&game.objects)
	for button, button_handle in all_objects_with_variant(&it, UIButton) {
		if game.clicked_ui_object != nil && game.clicked_ui_object != button_handle {continue}
		screen_aabb := get_texture_aabb_for_object(
			button.obj,
			game.final_transforms[button_handle.idx].transform,
		)
		hovering := is_point_in_aabb(mouse_screen_pos, screen_aabb)
		//TODO skip this stuff if there is another active UI interaction such as being in the middle of a slider drag
		scale_target := button.min_scale
		if hovering {
			scale_target = button.max_scale
		}
		button.scale *= 1 + (scale_target - button.scale) * 0.1
		// clicking := hovering && rl.IsMouseButtonDown(.LEFT)
		if hovering {
			button.color = SLATE_GRAY
			button.text_color = rl.DARKGRAY
		} else {
			button.color = rl.DARKGRAY
			button.text_color = SLATE_GRAY
		}
		click_started := hovering && rl.IsMouseButtonPressed(.LEFT)
		if click_started && button.on_click_start != nil {
			button.on_click_start({game, button, button_handle})
		}
		click_released := hovering && rl.IsMouseButtonReleased(.LEFT)
		if click_released && button.on_click != nil {
			button.on_click({game, button, button_handle})
		}
	}
}
