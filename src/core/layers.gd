class_name Layers
## Physics layer bits shared by every system (see project.godot layer names).

const STATIC := 1           # walls, floor, fixed furniture
const PROPS := 2            # rigid bodies (chairs, boxes, mugs...)
const CHARACTERS := 4
const INTERACT := 8         # interaction areas
const OCCLUDERS := 16       # blocks sight (opaque walls, big furniture)
const SOUND := 32           # blocks/attenuates sound (walls, doors, glass)
const TRIGGERS := 64        # slippery zones, room zones

const GROUP_NAV := &"nav_source"
