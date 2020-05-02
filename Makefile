start:
	nim -d:release -r c platformer

install:
	nimble install sdl2
	nimble install basic2d