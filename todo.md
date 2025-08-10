<!--This is a list of to dos so I don't lose track of what I am doing. 
Some of these are not strictly related to the project (e.g. it could be zig related)-->

## TODO
- [ ] Different screens / mode (Menu screen)
- [ ] Reactive buttons
- [ ] Add a proper test harness that is capabale of running the tests that has external dependencies
- [ ] Decouple util functions from alien asset
- [ ] Add states to alternate screens
- [ ] Draw order enforcement
- [ ] Background rendering
- [ ] Handling of in game events for different objects (or the interface of it)
- [ ] Particle effects / individual shaders
- [ ] Sound
- [ ] Fullscreen / window mode
- [ ] Pose changes

## DONE
- [x] Custom mouse cursor
- [x] Generic, standalone pushdown automata
- [x] Experiment with animation event
- [x] Render attachment type outside of region attachment 
- [x] Fix memory leak
- [x] Texture flipping
- [x] Animation switching / pausing
- [x] General event loop for user input
- [x] Use comptime to help us write `assets/assets.zig`
- [x] Figure out how to write tests in files that references files that are in the parent directories
- [x] Figure out how to write tests in files that utilizes C imports
- [x] Isolate common functions from objects and put them in util
- [x] Investigate into embedding assets in the binary so we don't have to mess around with paths during runtime
