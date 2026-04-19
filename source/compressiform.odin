package game

import "core:fmt"
import "core:math/linalg"
import "core:strings"
import "core:unicode/utf8"
import hm "handle_map_static"
import maps "mapgen"
import rl "vendor:raylib"

//boilerplate / starter code for your game-specific logic in this engine
GAME_NAME :: "compressiform"
UI_MAIN_FONT_SIZE :: 72
UI_SECONDARY_FONT_SIZE :: 42
IN_GAME_FONT_SIZE :: 36
BACKGROUND_MAP_COLOR :: rl.Color{128, 128, 128, 255}
CAMERA_MAP_COLOR :: rl.Color{99, 155, 255, 255}
LETTERS_PER_LINE :: 20
LINES_PER_TABLET :: 15
TABLET_STACK_FLOOR_TILE: TilemapTileId : {219, 188} //got this by measuring in world
TABLET_THUD_SCREENSHAKE_AMT :: 20
SCREENSHAKE_DECAY :: 18
@(rodata)
LEVELS := []Level {
	{
		target_message = "Made for Ludum Dare 2026 by Nathaniel Saxe and Ryan Kann",
		max_tablets = 1,
		time_limit = 120,
	},
	{
		target_message = "In a world where they never figured out paper, important messages are still sent overseas on stone tablets. You are in charge of compressing the longer messages to fit on a single stone tablet, saving your shipping company millions each year. First, let's do the basic due diligence of compacting the empty space in the message.",
		max_tablets = 1,
		time_limit = 180,
	},
	{target_message = "Now let's try another trick", max_tablets = 1, time_limit = 180},
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
}

SpawnType :: enum {
	None,
	Camera,
	Backglevel,
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
Tablet :: struct {}
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
		render_layer = uint(RenderLayer.Ceiling),
	},
}

//this keeps track of whether you are in the menu or in the game
GameStage :: enum {
	Start,
	Compressing,
	Scoring,
	GameOver,
}

//game-specific initialization logic (run once when game is started)
//typically this will be "set up the main menu"
game_start :: proc(game: ^Game) {
	game.color_to_tiletype[rl.BLACK] = .Wall
	game.color_to_tiletype[BACKGROUND_MAP_COLOR] = .None
	game.color_to_spawn[CAMERA_MAP_COLOR] = .Camera
	load_map :: proc() -> (tilemap: Tilemap, camera_spawn: TilemapTileId) {
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
	cam_spawn_tile: TilemapTileId
	game.global_tilemap, cam_spawn_tile = load_map()
	game.camera_spawn_point = get_tile_center(cam_spawn_tile)
	game.main_camera.position = game.camera_spawn_point
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
	game.stage = .Start
}

//game-specific teardown / reset logic
reset_game :: proc(g: ^Game = game) {
	hm.clear(&g.objects)
	clear(&g.chunks)
	clear(&g.loaded_chunks)
	recreate_final_transforms(g)
	g.frame_counter = 0
	g.screen_space_parent_handle = spawn_object(GameObject{name = "screen space parent"})
	g.tablet_stack_bottom = get_tile_center(TABLET_STACK_FLOOR_TILE) - {0, TILE_SIZE / 2}
}

//game-specific update logic (run once per frame)
game_update :: proc(game: ^Game, dt: f64) {
	timer := timer()
	switch game.stage {
	case .Start:
		game.level = LEVELS[game.level_number]
		level_start(game.level)
		rl.PlaySound(get_sound("tablet-whoosh.wav"))
		game.stage = .Compressing
	case .Compressing:
		if game.frame_counter % 3 == 0 {
			game.screen_shake = random_point_in_circle({0, 0}, game.screen_shake_amt)
		}
		game.screen_shake_amt = max(0, game.screen_shake_amt - SCREENSHAKE_DECAY * dt)
		game.main_camera.position += 1000 * dt * WASD()
		//do gravity
		{it := hm.make_iter(&game.objects)
			for obj in all_objects_with_tags(&it, .Collide) {
				GRAVITY_STRENGTH :: 800
				obj.acceleration.y += GRAVITY_STRENGTH
			}
		}
		mouse_screen_pos := linalg.to_f64(rl.GetMousePosition())
		mouse_pos := screen_to_world(linalg.to_f64(rl.GetMousePosition()), screen_conversion)
		mouse_tile := get_containing_tile(mouse_pos)
		{it := hm.make_iter(&game.objects)
			for obj, h in all_objects_with_variant(&it, Tablet) {
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
	case .GameOver:
	//show new game button
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


//figure out the line, column and tablet number of all the things in the message
//basically just laying out text into pages
set_message_element_positions :: proc(
	message: ^Message,
	letters_per_line, lines_per_tablet: int,
) -> (
	num_tablets_needed: int,
) {
	get_message_element_length :: proc(element: MessageElementContent) -> f64 {
		#partial switch content in element {
		case Word:
			return f64(len(content.str)) * content.letter_size
		}
		return 1
	}
	tablet := 0
	line := 0
	column: f64 = 0
	for &element in message {
		elem_len := get_message_element_length(element.content)
		column += elem_len
		//fix run off end of line
		if column > f64(letters_per_line) {
			column = elem_len
			line += 1
		}
		//fix run off end of tablet
		if line > lines_per_tablet {
			line = 0
			tablet += 1
		}
		element.position = {line, tablet, column - elem_len}
	}
	return tablet + 1
}
//make message from string
string_to_message :: proc(s: string) -> Message {
	result := Message{}
	for c in s {
		append(
			&result,
			MessageElement{content = Word{str = utf8.runes_to_string({c}), letter_size = 1}},
		)
	}
	return result
}

//called once at start of game
//called at start of level
spawn_tablets :: proc(level: Level, message: ^Message) {
	//divide message into tablet-sized chunks
	num_tablets := set_message_element_positions(message, LETTERS_PER_LINE, LINES_PER_TABLET)
	//for each chunk, spawn tablet displaying that message
	tablet_objects := [dynamic]GameObjectHandle{}
	for i in 0 ..< num_tablets {
		tablet_height :: 1500
		spawn_tablet(
			game.tablet_stack_bottom - f64(num_tablets - i) * vec2{0, tablet_height},
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
	tablet := GameObject {
		name = fmt.aprint("tablet", tablet_number),
		transform = {position = pos, scale = scale, pivot = {tex_dims.x / 2, tex_dims.y / 2}},
		render_info = {
			texture = tex,
			color = rl.WHITE,
			render_layer = uint(RenderLayer.Bullet),
			keep_original_dimensions = true,
		},
		velocity = {0, 100}, //throw it down
		hitbox = {layer = .Default, shape = AABB{min = (-tex_dims / 2), max = tex_dims / 2}},
		tags = {.Sprite, .Collide},
		variant = Tablet{},
	}
	return spawn_object(tablet)
}
//called from spawn_tablet
spawn_message_element_object :: proc(
	pos: vec2,
	element: MessageElement,
) -> GameObjectHandle {return {}}
level_start :: proc(level: Level) {
	message := string_to_message(level.target_message)
	spawn_tablets(level, &message)
}
level_end :: proc(level: Level) {}
level_score :: proc(level: Level) {}
// end_current_level :: proc() {}
get_axis :: proc(key_neg, key_pos: rl.KeyboardKey) -> f64 {
	return f64(int(rl.IsKeyDown(key_pos))) - f64(int(rl.IsKeyDown(key_neg)))
}
WASD :: proc() -> vec2 {
	return {get_axis(.A, .D), get_axis(.W, .S)}
}

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
			color = rl.WHITE,
			render_layer = uint(RenderLayer.UI),
			text_render_info = {font_size = UI_MAIN_FONT_SIZE},
		},
		tags = {.Sprite, .Text, .DoNotSerialize, .DontDestroyOnLoad},
		variant = UIButton {
			min_scale = min_scale,
			max_scale = {min_scale.x * 1.3, min_scale.y},
			on_click = on_click,
		},
		parent_handle = game.screen_space_parent_handle,
	}
	return spawn_object(button_obj)
}
