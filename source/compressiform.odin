package game

import "core:strconv"
import "core:strings"
import "core:unicode/utf8"
import maps "mapgen"
import rl "vendor:raylib"

//boilerplate / starter code for your game-specific logic in this engine
GAME_NAME :: "my game"
BACKGROUND_MAP_COLOR :: rl.Color{128, 128, 128, 255}
CAMERA_MAP_COLOR :: rl.Color{99, 155, 255, 255}


level_messages :: []string {
	"in a world where they never figured out paper and just kept writing stuff on stone tablets, somebody needs to",
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
	Player,
	Enemy,
	Checkpoint,
}

Round :: struct {
	time_limit, time_elapsed: f64,
	target_message:           string,
	message:                  Message,
}
Letter :: distinct struct {
	str:  string,
	size: f64,
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
Object :: distinct struct {
	type: MessageObjectType,
}
MessageElement :: union {
	Letter,
	Equals,
	Times,
	Object,
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
	clicked_ui_object:  Maybe(GameObjectHandle),
	dragged_object:     Maybe(GameObjectHandle),
	current_round:      Round,
	stage:              GameStage,
	menu_container:     GameObjectHandle,
	global_tilemap:     Tilemap `cbor:"-"`, //not serialized - too big
	chunk_loading_mode: ChunkLoadingMode,
	//we load the map immediately, but need to remember
	//where to spawn the player when the player object is spawned later
	player_spawn_point: vec2,
	player_handle:      GameObjectHandle,
	color_to_tiletype:  map[rl.Color]TileType,
	color_to_spawn:     map[rl.Color]SpawnType,
}

//object variants
//in contrast to tags, each object has exactly one variant
//GameObject has a field called `variant` which is this GameObjectVariant union type
//this is intended for mutually exclusive types of objects which need their own state fields
//for example, an enemy might need a max speed, state machine behavior, and an equipped weapon
//but those things will never apply to a collectible item
//so Enemy and Collectible can be two variants in the union
DefaultVariant :: distinct struct{}
GameObjectVariant :: union {
	DefaultVariant,
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
	Floor,
	Wall_Left,
	Wall_Right,
	Wall_Solid,
	Ceiling,
}
//properties of each type of tile
TILE_PROPERTIES := [TileType]TileTypeInfo {
	.None = {
		texture = atlas_textures[.None],
		render_layer = uint(RenderLayer.Floor),
		random_rotation = true,
	},
	.Floor = {
		collision = {layer = .Wall, resolve = true, trigger_events = true},
		texture = atlas_textures[.Rock],
		render_layer = uint(RenderLayer.Ceiling),
	},
	.Wall_Left = {
		collision = {layer = .Wall, resolve = true, trigger_events = true},
		texture = atlas_textures[.Rock],
		render_layer = uint(RenderLayer.Ceiling),
	},
	.Wall_Solid = {
		collision = {layer = .Wall, resolve = true, trigger_events = true},
		texture = atlas_textures[.Rock],
		render_layer = uint(RenderLayer.Ceiling),
	},
	.Wall_Right = {
		collision = {layer = .Wall, resolve = true, trigger_events = true},
		texture = atlas_textures[.Rock],
		render_layer = uint(RenderLayer.Ceiling),
	},
	.Ceiling = {
		collision = {layer = .Wall, resolve = true, trigger_events = true},
		texture = atlas_textures[.Rock],
		render_layer = uint(RenderLayer.Ceiling),
	},
}

//this keeps track of whether you are in the menu or in the game
GameStage :: enum {
	Compressing,
	Scoring,
	GameOver,
}

//game-specific initialization logic (run once when game is started)
//typically this will be "set up the main menu"
game_start :: proc(game: ^Game) {
	game.color_to_tiletype[rl.BLACK] = .Wall_Solid
	game.color_to_tiletype[BACKGROUND_MAP_COLOR] = .None
	game.color_to_spawn[CAMERA_MAP_COLOR] = .Player
	load_map :: proc() -> (tilemap: Tilemap, player_spawn: TilemapTileId) {
		MAP_DATA :: #load("map.png")
		tiles_img := rl.LoadImageFromMemory(".png", raw_data(MAP_DATA), i32(len(MAP_DATA)))
		tiles_buf := maps.img_to_buf(tiles_img, transpose = true)
		color_to_tile :: proc(c: rl.Color) -> Tile {
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
		return img_to_tilemap(tiles_buf, color_to_tile)
	}
}

//game-specific teardown / reset logic
reset_game :: proc(game: ^Game) {}

//game-specific update logic (run once per frame)
game_update :: proc(game: ^Game, dt: f64) {
	//update timer
	//if time is up, end the round
	//handle click & drag
	//on drag stop, update the round message
}

game_specific_load :: proc(game: ^Game = game, save: ^GameSave) {

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
		switch elem in element {
		case Letter:
			//first, attempt to parse
			idx := i
			num_str := elem.str
			//parse until non-number
			_, ok := strconv.parse_int(elem.str)
			for ok {
				idx += 1
				next_element := message[i]
				#partial switch next_el in next_element {
				case Letter:
					_, ok = strconv.parse_int(next_el.str)
					if !ok {
						break
					}
					num_str := strings.concatenate({num_str, next_el.str})
				case:
					break
				}
			}
		case Equals:
		case Times:
		case Object:
		}
	}
	return result
}

split_message :: proc(message: Message) -> []Message {}
//make message from string
string_to_message :: proc(s: string) -> Message {
	result := Message{}
	for c in s {
		append(&result, Letter{str = utf8.runes_to_string({c})})
	}
	return result
}

//called once at start of game
spawn_background :: proc() {}
//called at start of round
// spawn_tablets :: proc(message: Message) -> []GameObjectHandle {
//divide message into tablet-sized chunks
//for each chunk, spawn tablet displaying that message
// }
//called from spawn_tablets
// spawn_tablet :: proc(pos: vec2, message: Message) -> GameObjectHandle {}
//called from spawn_tablet
// spawn_letter :: proc(pos: vec2, message: MessageElement) -> GameObjectHandle {}
// reset_round :: proc() {}
// start_round :: proc(round:Round) {}
// score_round :: proc(round:Round) {}
// end_current_round :: proc() {}
