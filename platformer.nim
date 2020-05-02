import sdl2, sdl2/image, basic2d, strutils, times, math

type 
  SDLExecption = object of Exception

  Input {.pure.} = enum none, left, right, jump, restart, quit

  Collision {.pure.} = enum x, y, corner

  Player = ref object
    texture:TexturePtr
    pos: Point2d
    vel: Vector2d

  Map = ref object
    texture: TexturePtr
    width, height: int
    tiles: seq[uint8]

  Game = ref object
    inputs: array[Input, bool]
    renderer: RendererPtr
    player: Player
    map: Map
    camera: Vector2d

const
  tilesPerRow = 16
  tileSize: Point = (64.cint, 64.cint)
  windowSize: Point = (1280.cint, 720.cint)

  # BodyParts
  backFeetShadow = (x: 192.cint, y: 64.cint, w: 64.cint, h: 32.cint)
  bodyShadow = (x: 96.cint, y: 0.cint, w: 96.cint, h: 96.cint)
  frontFeetShadow= (x: 192.cint, y: 64.cint, w: 64.cint, h: 32.cint)
  backFeet= (x: 192.cint, y: 32.cint, w: 64.cint, h: 32.cint)
  body= (x: 0.cint, y: 0.cint, w: 96.cint, h: 96.cint)
  frontFeet= (x: 192.cint, y: 32.cint, w: 64.cint, h: 32.cint)
  leftEye= (x: 64.cint, y: 96.cint, w: 32.cint, h: 32.cint)
  rightEye= (x: 64.cint, y: 96.cint, w: 32.cint, h: 32.cint)

  playerSize = vector2d(64, 64)

  air = 0
  start = 78
  finish = 110

template sdlFailIf(cond: typed, reason: string) =
  if cond: raise SDLExecption.newException(
      reason & ", SDL error: " & $getError() 
  )

proc renderTee(renderer: RendererPtr, texture: TexturePtr, pos: Point2d) =
  let
    x = pos.x.cint
    y = pos.y.cint

  var bodyParts: array[8, tuple[source, dest: Rect, flip: cint]] = [
    # back feet shadow
    (rect(backFeetShadow.x, backFeetShadow.y, backFeetShadow.w, backFeetShadow.h), rect(x-60, y, 96, 48),
     SDL_FLIP_NONE),
     # body shadow
    (rect(bodyShadow.x, bodyShadow.y, bodyShadow.w, bodyShadow.h), rect(x-48, y-48, 96, 96),
     SDL_FLIP_NONE),
    # front feet shadow
    (rect(frontFeetShadow.x, frontFeetShadow.y, frontFeetShadow.w, frontFeetShadow.h), rect(x-36, y, 96, 48),
     SDL_FLIP_NONE),
    # back feet
    (rect(backFeet.x, backFeet.y, backFeet.w, backFeet.h), rect(x-60, y, 96, 48),
     SDL_FLIP_NONE), 
    # body
    (rect(body.x, body.y, body.w, body.h), rect(x-48, y-48, 96, 96),
     SDL_FLIP_NONE),
    # front feet
    (rect(frontFeet.x, frontFeet.y, frontFeet.w, frontFeet.h), rect(x-36, y, 96, 48),
     SDL_FLIP_NONE),
    # left eye
    (rect(leftEye.x, leftEye.y, leftEye.w, leftEye.h), rect(x-18, y-21, 36, 36),
     SDL_FLIP_NONE),
    # right eye
    (rect(rightEye.x, rightEye.y, rightEye.w, rightEye.h), rect( x-6, y-21, 36, 36),
     SDL_FLIP_HORIZONTAL)
  ]

  for part in bodyParts.mitems:
    renderer.copyEx(texture, part.source, part.dest, angle=0.0,
                    center = nil, flip = part.flip)

proc renderMap(renderer: RendererPtr, map: Map, camera: Vector2d) =
  var
    clip = rect(0, 0, tileSize.x, tileSize.y)
    dest = rect(0, 0, tileSize.x, tileSize.y)

  for i, tileNr in map.tiles:
    if tileNr == 0: continue

    clip.x = cint(tileNr mod tilesPerRow) * tileSize.x
    clip.y = cint(tileNr div tilesPerRow) * tileSize.y
    dest.x = cint(i mod map.width) * tileSize.x - camera.x.cint
    dest.y = cint(i div map.width) * tileSize.y - camera.y.cint

    renderer.copy(map.texture, unsafeAddr clip, unsafeAddr dest)

proc restartPlayer(player: Player) =
  player.pos = point2d(170, 500)
  player.vel = vector2d(0, 0)

proc newPlayer(texture: TexturePtr): Player =
  new result
  result.restartPlayer()
  result.texture = texture

proc newMap(texture: TexturePtr, file: string): Map =
  new result
  result.texture = texture
  result.tiles = @[]
  for line in file.lines:
    var width = 0
    for word in line.split(' '):
      if word == "": continue
      let value = parseUInt(word)
      if value > uint(uint8.high):
        raise ValueError.newException(
          "Invalid value " & word & " in map " & file)
      result.tiles.add value.uint8
      inc width

    if result.width > 0 and result.width != width:
      raise ValueError.newException(
        "Incompatible line length in map " & file)
    result.width = width
    inc result.height

proc newGame(renderer: RendererPtr): Game =
  new result
  result.renderer = renderer
  result.player = newPlayer(renderer.loadTexture("./image/player.png"))
  result.map = newMap(renderer.loadTexture("./image/grass.png"), "./map/default.map")

proc toInput(key: Scancode): Input =
  case key
  of SDL_SCANCODE_LEFT: Input.left
  of SDL_SCANCODE_RIGHT: Input.right
  of SDL_SCANCODE_SPACE: Input.jump
  of SDL_SCANCODE_R: Input.restart
  of SDL_SCANCODE_Q: Input.quit
  else: Input.none

proc handleInput(game: Game) =
  var event = defaultEvent
  while pollEvent(event):
    case event.kind
    of QuitEvent:
      game.inputs[Input.quit] = true
    of KeyDown:
      game.inputs[event.key.keysym.scancode.toInput] = true
    of KeyUp:
      game.inputs[event.key.keysym.scancode.toInput] = false
    else:
      discard

proc render(game: Game) =
  # Draw over all drawings of the last frame with the default color
  game.renderer.clear()
  game.renderer.renderTee(game.player.texture, game.player.pos - game.camera)
  game.renderer.renderMap(game.map, game.camera)
  # Show the result on screen
  game.renderer.present()

proc getTile(map: Map, x, y: int): uint8 =
  let
    nx = clamp(x div tileSize.x, 0, map.width - 1)
    ny = clamp(y div tileSize.y, 0, map.height - 1)
    pos = ny * map.width + nx

  map.tiles[pos]

proc isSolid(map: Map, x, y: int): bool =
  map.getTile(x, y) notin {air, start, finish}

proc isSolid(map: Map, point: Point2d): bool =
  map.isSolid(point.x.round.int, point.y.round.int)

proc onGround(map: Map, pos: Point2d, size: Vector2d): bool =
  let size = size * 0.5
  result =
    map.isSolid(point2d(pos.x - size.x, pos.y + size.y + 1)) or
    map.isSolid(point2d(pos.x + size.x, pos.y + size.y + 1))

proc testBox(map: Map, pos: Point2d, size: Vector2d): bool =
  let size = size * 0.5
  result =
    map.isSolid(point2d(pos.x - size.x, pos.y - size.y)) or
    map.isSolid(point2d(pos.x + size.x, pos.y - size.y)) or
    map.isSolid(point2d(pos.x - size.x, pos.y + size.y)) or
    map.isSolid(point2d(pos.x + size.x, pos.y + size.y))

proc moveBox(map: Map, pos: var Point2d, vel: var Vector2d,
             size: Vector2d): set[Collision] {.discardable.} =
  let distance = vel.len
  let maximum = distance.int

  if distance < 0:
    return

  let fraction = 1.0 / float(maximum + 1)

  for i in 0 .. maximum:
    var newPos = pos + vel * fraction

    if map.testBox(newPos, size):
      var hit = false

      if map.testBox(point2d(pos.x, newPos.y), size):
        result.incl Collision.y
        newPos.y = pos.y
        vel.y = 0
        hit = true

      if map.testBox(point2d(newPos.x, pos.y), size):
        result.incl Collision.x
        newPos.x = pos.x
        vel.x = 0
        hit = true

      if not hit:
        result.incl Collision.corner
        newPos = pos
        vel = vector2d(0, 0)

    pos = newPos

proc physics(game: Game) =
  if game.inputs[Input.restart]:
    game.player.restartPlayer()

  let ground = game.map.onGround(game.player.pos, playerSize)

  if game.inputs[Input.jump]:
    if ground:
      game.player.vel.y = -21

  let direction = float(game.inputs[Input.right].int -
                        game.inputs[Input.left].int)

  game.player.vel.y += 0.75
  if ground:
    game.player.vel.x = 0.5 * game.player.vel.x + 4.0 * direction
  else:
    game.player.vel.x = 0.95 * game.player.vel.x + 2.0 * direction
  game.player.vel.x = clamp(game.player.vel.x, -8, 8)

  game.map.moveBox(game.player.pos, game.player.vel, playerSize)

proc moveCamera(game: Game) =
  const halfWin = float(windowSize.x div 2)
  let
    leftArea  = game.player.pos.x - halfWin - 100
    rightArea = game.player.pos.x - halfWin + 100
  game.camera.x = clamp(game.camera.x, leftArea, rightArea)

proc main = 
  sdlFailIf(not sdl2.init(INIT_VIDEO or INIT_TIMER or INIT_EVENTS)):
    "SDL2 initialization failed"
  defer: sdl2.quit()

  sdlFailIf(not setHint("SDL_RENDER_SCALE_QUALITY", "2")):
    "Linear texture filtering could not be enabled"

  const imgFlags: cint = IMG_INIT_PNG
  sdlFailIf(image.init(imgFlags) != imgFlags):
    "SDL2 Image initialization failed"
  defer: image.quit()

  let window = createWindow(title = "Our own 2D platformer",
    x = SDL_WINDOWPOS_CENTERED, y = SDL_WINDOWPOS_CENTERED,
    w = 1280, h = 720, flags = SDL_WINDOW_SHOWN)
  sdlFailIf window.isNil: "Window could not be created"
  defer: window.destroy()

  let renderer = window.createRenderer(index = -1,
    flags = Renderer_Accelerated or Renderer_PresentVsync)
  sdlFailIf render.isNil: "Render could not be created"
  defer: renderer.destroy()

  renderer.setDrawColor(r = 110, g = 132, b = 174)

  var
    game = newGame(renderer)
    startTime = epochTime()
    lastTick = 0

  # Game loop
  while not game.inputs[Input.quit]:
    game.handleInput()

    let newTick = int((epochTime() - startTime) * 50)
    for tick in lastTick+1 .. newTick:
      game.physics()
      game.moveCamera()
    lastTick = newTick

    game.render()

main()