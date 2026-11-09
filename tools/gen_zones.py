"""Generates the story's open zones as map files (maps/<id>.json, listed in maps/index.json), for
fine-tuning in the map editor afterwards. Each zone is a seeded layout: a wide open area with rock
outcrops (walls), roads carved between its landmarks so everything is reachable, the landmarks'
props, NPCs, quest objects and triggers, and monster packs spread through it (themed by area).

Usage:  python tools/gen_zones.py            (rewrites every zone below; edits made in the editor
                                               to those maps are lost, so copy a map first)
"""
import json
import math
import os
import random
from collections import deque

ROOT = os.path.join(os.path.dirname(__file__), "..")
MAPS = os.path.join(ROOT, "maps")
CELL = 128


def cell_pos(c, dx=0.5, dy=0.5):
    return int((c[0] + dx) * CELL), int((c[1] + dy) * CELL)


class Zone:
    def __init__(self, zid, name, cols, rows, seed, theme):
        self.id, self.name, self.cols, self.rows, self.theme = zid, name, cols, rows, theme
        self.rng = random.Random(seed)
        self.wall = [[False] * cols for _ in range(rows)]
        self.objects = []
        self.keep_clear = []  # (cell, radius): no outcrops here
        self.roads = [["."] * cols for _ in range(rows)]  # the roads layer: "." none, "d" dirt path, "s" cobblestone
        self.lamp_cells = []  # cells of painted paths, in order, for lamp posts along them
        self.water = [["."] * cols for _ in range(rows)]  # the water layer: "." none, "~" river, "=" bridge

    # ---- terrain ----
    def outcrops(self, count, rmin, rmax):
        for _ in range(count):
            cx, cy = self.rng.randrange(self.cols), self.rng.randrange(self.rows)
            rx, ry = self.rng.uniform(rmin, rmax), self.rng.uniform(rmin, rmax) * 0.8
            for y in range(int(cy - ry - 2), int(cy + ry + 3)):
                for x in range(int(cx - rx - 2), int(cx + rx + 3)):
                    if 0 <= x < self.cols and 0 <= y < self.rows:
                        d = ((x - cx) / rx) ** 2 + ((y - cy) / ry) ** 2
                        if d < 1.0 + self.rng.uniform(-0.35, 0.25):
                            self.wall[y][x] = True

    def border(self, thick=2):
        for y in range(self.rows):
            for x in range(self.cols):
                t = thick + (1 if self.rng.random() < 0.35 else 0)
                if x < t or y < t or x >= self.cols - t or y >= self.rows - t:
                    self.wall[y][x] = True

    def smooth(self, rounds=2):
        for _ in range(rounds):
            new = [row[:] for row in self.wall]
            for y in range(1, self.rows - 1):
                for x in range(1, self.cols - 1):
                    n = sum(self.wall[y + dy][x + dx] for dy in (-1, 0, 1) for dx in (-1, 0, 1)) - self.wall[y][x]
                    if n >= 5:
                        new[y][x] = True
                    elif n <= 2:
                        new[y][x] = False
            self.wall = new

    def clear(self, c, r):
        for y in range(c[1] - r, c[1] + r + 1):
            for x in range(c[0] - r, c[0] + r + 1):
                if 1 <= x < self.cols - 1 and 1 <= y < self.rows - 1 and (x - c[0]) ** 2 + (y - c[1]) ** 2 <= r * r + 1:
                    self.wall[y][x] = False

    def hall(self, x0, y0, x1, y1):
        """A rectangular chamber (cells x0..x1, y0..y1, both ends included) cut out of solid rock."""
        for y in range(y0, y1 + 1):
            for x in range(x0, x1 + 1):
                if 1 <= x < self.cols - 1 and 1 <= y < self.rows - 1:
                    self.wall[y][x] = False

    def hallway(self, a, b, w=3, first="x"):
        """A straight-walled corridor `w` cells wide from a to b: along x first (or y first), then the other way. Returns
        the cells of its middle, in order."""
        corner = (b[0], a[1]) if first == "x" else (a[0], b[1])
        trail = []
        for p, q in [(a, corner), (corner, b)]:
            x, y = p
            while True:
                trail.append((x, y))
                if (x, y) == q:
                    break
                x += (q[0] > x) - (q[0] < x)
                y += (q[1] > y) - (q[1] < y)
        out = []
        for c in trail:
            if not out or out[-1] != c:
                out.append(c)
        for x, y in out:
            for dy in range(-(w // 2), w - w // 2):
                for dx in range(-(w // 2), w - w // 2):
                    if 1 <= x + dx < self.cols - 1 and 1 <= y + dy < self.rows - 1:
                        self.wall[y + dy][x + dx] = False
        return out

    def paint(self, c, ch):
        if 0 <= c[0] < self.cols and 0 <= c[1] < self.rows and not self.wall[c[1]][c[0]]:
            self.roads[c[1]][c[0]] = ch

    def plaza(self, c, r, ch="s"):
        """A square of paving (cobblestone by default), `r` cells to each side of c."""
        for y in range(c[1] - r, c[1] + r + 1):
            for x in range(c[0] - r, c[0] + r + 1):
                self.paint((x, y), ch)

    def route(self, a, b, ch="d"):
        """Lays a path on the ground (the roads layer) from a to b over open floor: the shortest way with few turns,
        and a cheap one over a path already laid, so paths that head the same way share their line and the network
        reads as roads, not a tangle. Call it once the terrain is final."""
        import heapq
        start, goal = tuple(a), tuple(b)
        best = {(start, None): 0.0}
        prev = {}
        heap = [(0.0, start, None)]
        end = None
        while heap:
            cost, cur, d = heapq.heappop(heap)
            if cost > best.get((cur, d), 1e9):
                continue
            if cur == goal:
                end = (cur, d)
                break
            for nd in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                nx, ny = cur[0] + nd[0], cur[1] + nd[1]
                if not (1 <= nx < self.cols - 1 and 1 <= ny < self.rows - 1) or self.wall[ny][nx]:
                    continue
                step = 0.35 if self.roads[ny][nx] != "." else 1.0
                if d is not None and nd != d:
                    step += 0.9  # a turn
                nc = cost + step
                if nc < best.get(((nx, ny), nd), 1e9):
                    best[((nx, ny), nd)] = nc
                    prev[((nx, ny), nd)] = (cur, d)
                    heapq.heappush(heap, (nc, (nx, ny), nd))
        trail = []
        node = end
        while node is not None:
            trail.append(node[0])
            node = prev.get(node)
        trail.reverse()
        for c in trail:
            if self.roads[c[1]][c[0]] == ".":
                self.paint(c, ch)
        self.lamp_cells.append(trail)
        return trail

    def road(self, a, b, width=1):
        """A wandering road from a to b (cells), `width` cells to each side of its middle: the corridor is cleared of
        outcrops (the path itself is laid by route() afterwards)."""
        x, y = a
        while (x, y) != tuple(b):
            self.clear((x, y), width)
            dx, dy = b[0] - x, b[1] - y
            if self.rng.random() < 0.25:  # wander
                step = self.rng.choice([(1, 0), (-1, 0), (0, 1), (0, -1)])
            elif abs(dx) > abs(dy):
                step = (1 if dx > 0 else -1, 0)
            else:
                step = (0, 1 if dy > 0 else -1)
            x = min(max(x + step[0], 2), self.cols - 3)
            y = min(max(y + step[1], 2), self.rows - 3)
        self.clear(b, width)

    def river(self, points):
        """A river a cell wide along straight segments between the (col, row) `points`, edge to edge for a map: its
        cells are water in the water layer and walls in the grid (a bridge() makes a crossing)."""
        cells = []
        for a, b in zip(points, points[1:]):
            x, y = a
            while (x, y) != tuple(b):
                cells.append((x, y))
                x += (b[0] > x) - (b[0] < x)
                y += (b[1] > y) - (b[1] < y)
        cells.append(tuple(points[-1]))
        for x, y in cells:
            self.wall[y][x] = True
            self.water[y][x] = "~"
            self.roads[y][x] = "."
        return cells

    def fill(self):
        """Solid rock everywhere: carve chambers (clear) and tunnels (road) out of it."""
        self.wall = [[True] * self.cols for _ in range(self.rows)]

    def mire(self, c, r, wobble=0.35):
        """Boggy shallows (the water layer's \",\"): floor you can walk, slowly, in a rough circle."""
        for y in range(c[1] - r - 1, c[1] + r + 2):
            for x in range(c[0] - r - 1, c[0] + r + 2):
                if 2 <= x < self.cols - 2 and 2 <= y < self.rows - 2 and not self.wall[y][x] and self.water[y][x] == "." and self.roads[y][x] == ".":
                    if math.dist((x, y), c) < r * (1.0 + self.rng.uniform(-wobble, wobble)):
                        self.water[y][x] = ","

    def exit_near(self, target, wanted, label_prop=None):
        """An exit to the zone `target` on the open floor nearest `wanted`; returns its cell."""
        best = None
        for y in range(2, self.rows - 2):
            for x in range(2, self.cols - 2):
                if self.open_around((x, y), 1) and self.water[y][x] == ".":
                    if best is None or math.dist((x, y), wanted) < math.dist(best, wanted):
                        best = (x, y)
        self.add("portal", best, target=target)
        return best

    def bridge_near(self, cells, wanted, reach=3):
        """Makes a bridge of the river cell nearest `wanted` (col, row) where open ground lies on both banks, two cells deep, so
        a road already carved there leads onto it. Returns the cell."""
        best = None
        for x, y in cells:
            if 3 <= x < self.cols - 3 and all(not self.wall[y][x + d] for d in range(-reach, reach + 1) if d != 0):
                if self.wall[y - 1][x] and self.wall[y + 1][x] and self.water[y - 1][x] == "~" and self.water[y + 1][x] == "~":
                    if best is None or math.dist((x, y), wanted) < math.dist(best, wanted):
                        best = (x, y)
        assert best is not None, "no place for a bridge near %s" % (wanted,)
        self.bridge(best)
        return best

    def bridge(self, c):
        """A river cell made a bridge: floor you can cross, with a deck over the water."""
        assert self.water[c[1]][c[0]] == "~", c
        self.wall[c[1]][c[0]] = False
        self.water[c[1]][c[0]] = "="

    def terrace(self, c, w, h, stairs, trees=True, tree_ids=(1, 2, 3, 4, 6, 7, 8, 9, 10)):
        """Raised ground you can walk on (MazeMap._add_terraces): a footprint of w x h cells from c, a ring of wall (left,
        right, top) round the floor, its bottom row the cliff face, with the columns `stairs` (counted from the footprint's
        left) as steps down. The ring is lined with trees and rocks, so you see why you can't walk off the edge."""
        x0, y0 = c
        for y in range(y0, y0 + h):
            for x in range(x0, x0 + w):
                self.wall[y][x] = True
                self.roads[y][x] = "."
        for y in range(y0 + 1, y0 + h - 1):
            for x in range(x0 + 1, x0 + w - 1):
                self.wall[y][x] = False
        for s in stairs:
            self.wall[y0 + h - 1][x0 + s] = False
        self.objects.append({"type": "terrace", "x": x0, "y": y0, "w": w, "h": h, "stairs": list(stairs)})
        if trees:
            ring = [(x, y0) for x in range(x0, x0 + w)] + [(x0, y) for y in range(y0 + 1, y0 + h - 1)] + [(x0 + w - 1, y) for y in range(y0 + 1, y0 + h - 1)]
            for i, (x, y) in enumerate(ring):
                if i % 2 == 0 or y == y0:
                    self.prop("tree_" + str(self.rng.choice(list(tree_ids))), (x, y), dx=self.rng.uniform(0.3, 0.7), dy=self.rng.uniform(0.6, 0.95), scale=self.rng.uniform(0.5, 0.65))
                else:
                    self.prop("stones_" + str(self.rng.choice([1, 2, 3, 4, 5, 6])), (x, y), dx=0.5, dy=0.8, scale=0.45)

    def lamps(self, every=6, scale=0.45, sprite="decor_4"):
        """A lamp post at the edge of each painted path, every `every` cells along it, on whichever side is open."""
        for trail in self.lamp_cells:
            for i in range(3, len(trail), every):
                x, y = trail[i]
                for dx, dy in ((0, -1), (0, 1), (1, 0), (-1, 0)):
                    nx, ny = x + dx, y + dy
                    if 1 <= nx < self.cols - 1 and 1 <= ny < self.rows - 1 and not self.wall[ny][nx] and self.roads[ny][nx] == ".":
                        self.prop(sprite, (nx, ny), dx=0.5 + dx * 0.0, dy=0.9, scale=scale)
                        break

    def reachable_only(self, start):
        seen = [[False] * self.cols for _ in range(self.rows)]
        q = deque([start])
        seen[start[1]][start[0]] = True
        while q:
            x, y = q.popleft()
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                nx, ny = x + dx, y + dy
                if 0 <= nx < self.cols and 0 <= ny < self.rows and not self.wall[ny][nx] and not seen[ny][nx]:
                    seen[ny][nx] = True
                    q.append((nx, ny))
        for y in range(self.rows):
            for x in range(self.cols):
                if not self.wall[y][x] and not seen[y][x]:
                    self.wall[y][x] = True
        return seen

    def open_around(self, c, r=1):
        return all(not self.wall[y][x] for y in range(c[1] - r, c[1] + r + 1) for x in range(c[0] - r, c[0] + r + 1)
                   if 0 <= x < self.cols and 0 <= y < self.rows)

    # ---- objects ----
    def add(self, type_, c, dx=0.5, dy=0.5, **kw):
        x, y = cell_pos(c, dx, dy)
        o = {"type": type_, "x": x, "y": y}
        o.update(kw)
        self.objects.append(o)
        return o

    def prop(self, sprite, c, dx=0.5, dy=0.5, scale=0.5, solid=False):
        return self.add("prop", c, dx, dy, sprite=sprite, scale=scale, solid=solid)

    def packs(self, count, avoid, themes, min_gap=7, min_start=10, start=None):
        """`themes`: [(cell, radius, kind)]; a pack in one of those circles is that kind."""
        placed = []
        tries = 0
        while len(placed) < count and tries < 6000:
            tries += 1
            c = (self.rng.randrange(3, self.cols - 3), self.rng.randrange(3, self.rows - 3))
            if not self.open_around(c, 1):
                continue
            if start and math.dist(c, start) < min_start:
                continue
            if any(math.dist(c, p) < min_gap for p in placed) or any(math.dist(c, a) < r for a, r in avoid):
                continue
            kind = ""
            for tc, tr, tk in themes:
                if math.dist(c, tc) < tr:
                    kind = tk
                    break
            placed.append(c)
            o = {"min": 3, "max": 5}
            if kind:
                o["kind"] = kind
            self.add("pack", c, **o)
        return placed

    def save(self, area_name_kind="story"):
        grid = ["".join("#" if w else "." for w in row) for row in self.wall]
        data = {"format": 1, "id": self.id, "name": self.name, "kind": area_name_kind, "theme": self.theme,
                "cell": CELL, "auto_decorate": True, "grid": grid, "objects": self.objects}
        if any(ch != "." for row in self.roads for ch in row):
            data["roads"] = ["".join(row) for row in self.roads]
        if any(ch != "." for row in self.water for ch in row):
            data["water"] = ["".join(row) for row in self.water]
        with open(os.path.join(MAPS, self.id + ".json"), "w") as f:
            json.dump(data, f, indent="\t")
        idx_path = os.path.join(MAPS, "index.json")
        idx = json.load(open(idx_path))
        idx["maps"][self.id] = {"kind": area_name_kind, "name": self.name}
        with open(idx_path, "w") as f:
            json.dump(idx, f, indent="\t", sort_keys=True)
        print("wrote", self.id, "%dx%d" % (self.cols, self.rows), sum(o["type"] == "pack" for o in self.objects), "packs")


def dune_wastes():
    """Act 1's first zone, the Blackroot Wilds (Act I: The Bleeding Veil, see ACT1_DESIGN.md): mist-choked woodland
    west of Oakhaven Outpost, its oaks dead, thorn barricades across the paths on, tainted beasts about. The id is
    from when it was a desert, kept so saved waypoints and zone ids still find it. A hunting lodge where Scout
    Captain Dennis is pinned by the briarwolves and their alpha (Chapter 1), a ruined manor with the merchant's
    lockbox (The Lost Heirloom), and a waypoint. Dead trees, stumps and tainted pools are the woodland's own
    props; skulls and wagons are borrowed from the desert theme ("desert/...")."""
    z = Zone("dune_wastes", "Blackroot Wilds", 70, 46, seed=2207, theme="woodland")
    start = (4, 23)
    waypoint = (16, 25)
    lodge = (46, 11)
    manor = (53, 34)
    gate_a, gate_b, gate_c = (10, 17), (11, 30), (17, 21)  # the packs by the road from the outpost (Chapter 1: clear the gate)
    glade = (30, 27)
    fungus = (24, 10)
    landmarks = [(start, 4), (waypoint, 3), (lodge, 6), (manor, 5), (glade, 4), (fungus, 4), (gate_a, 2), (gate_b, 2), (gate_c, 2)]

    z.outcrops(90, 1.5, 5.0)
    z.border(2)
    z.smooth(2)
    for c, r in landmarks:
        z.clear(c, r)
    z.road(start, waypoint, 1)
    z.road(waypoint, gate_c, 1)
    z.road(gate_c, glade, 1)
    z.road(glade, manor, 1)
    z.road(glade, lodge, 1)
    z.road(waypoint, gate_a, 1)
    z.road(waypoint, gate_b, 1)
    z.road(lodge, fungus, 1)
    # A river down the Wilds between the glade and the lodge and manor, crossed by two bridges (the roads use them)
    river = z.river([(36, 0), (36, 20), (38, 20), (38, 45)])
    bridge_a = z.bridge_near(river, (36, 14))
    bridge_b = z.bridge_near(river, (38, 31))
    z.reachable_only(start)

    # The ways on: east into the Weeping Hollow's cave mouth, south down into the Sunken Fen
    hollow_exit = z.exit_near("weeping_hollow", (62, 22))
    fen_exit = z.exit_near("sunken_fen", (46, 41))
    z.prop("desert/decor_6", (hollow_exit[0] + 1, hollow_exit[1] - 1), scale=0.4)
    z.prop("stones_1", (hollow_exit[0] + 1, hollow_exit[1] + 1), scale=0.5)
    z.prop("tree_12", (fen_exit[0] - 1, fen_exit[1] + 1), scale=0.7)
    z.prop("decor_14", (fen_exit[0] + 1, fen_exit[1] - 1), scale=0.4)

    # The paths on the ground: one dirt road network (shared where it heads the same way), cobblestone where it
    # reaches somewhere: the gate, the waypoint, the lodge's yard and the manor's forecourt
    for a, b in [(start, waypoint), (waypoint, gate_c), (gate_c, glade), (glade, manor), (glade, lodge),
                 (waypoint, gate_a), (waypoint, gate_b), (lodge, fungus), (manor, hollow_exit), (manor, fen_exit)]:
        z.route(a, b, "d")
    z.plaza(start, 1)
    z.plaza(waypoint, 1)
    z.plaza((lodge[0], lodge[1] + 1), 1)
    z.plaza((manor[0], manor[1] + 1), 1)
    z.lamps()

    # The road from Oakhaven comes in on the west edge
    z.add("start", start)
    z.add("portal", (start[0] - 2, start[1]), target="town")
    z.clear((start[0] - 2, start[1]), 1)
    z.add("waypoint", waypoint)
    z.prop("decor_9", (start[0] + 2, start[1] - 2), scale=0.5)  # signpost
    z.prop("decor_15", (start[0] + 2, start[1] + 2), scale=0.5, solid=True)  # the gate's last palisade
    z.prop("decor_12", (36, 6), dx=0.5, dy=0.7, scale=0.4)  # a rotting boat on the river, and signposts at its bridges
    z.prop("decor_12", (38, 38), dx=0.5, dy=0.7, scale=0.4)
    z.prop("decor_9", (35, 14), dx=0.5, scale=0.5)
    z.prop("decor_9", (37, 31), dx=0.5, scale=0.5)
    z.prop("decor_4", (start[0] + 1, start[1] - 1), dx=0.2, scale=0.45)  # lamp posts at the gate and the waypoint
    z.prop("decor_4", (start[0] + 1, start[1] + 1), dx=0.2, scale=0.45)
    z.prop("decor_4", (waypoint[0] - 1, waypoint[1] - 1), dx=0.3, scale=0.45)
    z.prop("decor_4", (waypoint[0] + 1, waypoint[1] + 1), dx=0.7, scale=0.45)

    # The hunting lodge: Dennis pinned inside, the alpha and its pack round it, the rift shard where it falls
    z.add("trigger", lodge, radius=420, id="hunting_lodge",
          text="A hunting lodge, its door barred from outside. Something inside is shouting.")
    z.prop("building_5", (lodge[0] - 1, lodge[1] - 3), scale=0.5, solid=True)
    z.prop("decor_15", (lodge[0] - 4, lodge[1] - 1), scale=0.5, solid=True)  # thorn barricade across the path
    z.prop("decor_15", (lodge[0] + 3, lodge[1] - 1), scale=0.5, solid=True)
    z.prop("decor_8", (lodge[0] + 4, lodge[1] - 3), scale=0.45, solid=True)  # woodpile
    z.prop("decor_1", (lodge[0] - 2, lodge[1] - 2), scale=0.45)  # a hanging lantern at the door
    z.prop("decor_5", (lodge[0], lodge[1] + 2), scale=0.5)  # tainted pool
    z.prop("tree_11", (lodge[0] - 5, lodge[1] - 3), scale=0.7)
    z.prop("tree_12", (lodge[0] + 5, lodge[1] + 1), scale=0.7)
    z.prop("desert/decor_6", (lodge[0] + 2, lodge[1] + 3), scale=0.4)  # bones
    z.add("npc", (lodge[0] - 1, lodge[1] - 1), id="dennis", facing=1)
    z.add("boss", (lodge[0] + 2, lodge[1] + 1), id="briar_alpha", name="The Briarwolf Alpha",
          kind="briarwolf", skin="gnoll", hp=5.0, size=1.5)
    z.add("quest_object", (lodge[0] + 3, lodge[1] + 2), id="rift_shard", sprite="", prompt="Take the Coagulated Rift Shard",
          text="You pry the Coagulated Rift Shard from the alpha's flank. It is cold, oily and faintly red, and it hums.")
    for dx, dy in [(-4, 3), (5, 3), (0, 5)]:
        c = (lodge[0] + dx, lodge[1] + dy)
        z.clear(c, 1)
        z.add("pack", c, min=3, max=4, kind="briarwolf")

    # The ruined manor: a family lockbox, and what was done to keep it
    z.add("trigger", manor, radius=420, id="ruined_manor",
          text="A manor, roofless and black with rot. Someone hid something in here.")
    z.prop("building_3", (manor[0], manor[1] - 3), scale=0.55, solid=True)
    z.prop("building_4", (manor[0] + 4, manor[1] - 2), scale=0.5, solid=True)  # its tower
    z.prop("decor_15", (manor[0] - 4, manor[1] + 1), scale=0.5, solid=True)
    z.prop("decor_16", (manor[0] - 2, manor[1] + 2), scale=0.5)  # scarecrow
    z.prop("decor_4", (manor[0] - 1, manor[1] + 3), dx=0.2, scale=0.45)  # the forecourt's lamp posts, one still lit
    z.prop("decor_4", (manor[0] + 2, manor[1] + 3), dx=0.8, scale=0.45)
    z.prop("decor_7", (manor[0] + 1, manor[1] + 1), scale=0.5)
    z.prop("tree_12", (manor[0] - 5, manor[1] - 2), scale=0.7)
    z.prop("tree_11", (manor[0] + 6, manor[1] + 2), scale=0.7)
    z.prop("desert/decor_6", (manor[0] + 2, manor[1] + 3), scale=0.4)
    z.add("quest_object", (manor[0] + 1, manor[1] - 1), id="lockbox", sprite="", prompt="Open the lockbox",
          text="Inside the lockbox: a merchant's ledger, and a diary. 'The servants were slow to die, but the thing in the "
               "cellar was patient, and it let us through the Wilds untouched. Corwin' ... He fed his own household to the "
               "Taint, and took his gem and walked away.")

    # The glade and the fungus hollow: dead oaks, stumps, tainted pools
    for dx, dy in [(-3, -2), (3, -2), (-2, 3), (4, 2), (0, -4)]:
        z.prop("tree_" + str(z.rng.choice([11, 12, 11, 12, 5])), (glade[0] + dx, glade[1] + dy), scale=0.65)
    z.prop("decor_6", (glade[0], glade[1]), scale=0.55)
    z.prop("tree_14", (glade[0] - 1, glade[1] + 2), scale=0.55)
    for dx, dy in [(-3, 0), (2, 2), (3, -2), (-1, -3)]:
        z.prop("decor_14", (fungus[0] + dx, fungus[1] + dy), scale=0.4)  # fungal blooms
    z.prop("tree_13", (fungus[0] + 1, fungus[1]), scale=0.55)
    # The paths on are choked with thorn barricades (the Weeping Hollow and the Sunken Fen come later)

    themes = [(gate_a, 6, "briarwolf"), (gate_b, 6, "briarwolf"), (gate_c, 6, "briarwolf"), (lodge, 13, "briarwolf"),
              (manor, 10, "ghoul"), (glade, 8, "villager"), (fungus, 7, "zombie")]
    avoid = [(start, 9), (waypoint, 4), (lodge, 3), (manor, 3)]
    z.packs(24, avoid, themes, min_gap=7, start=start)
    for c in (gate_a, gate_b, gate_c):  # the packs the first chapter clears from round the gate road
        z.add("pack", c, min=3, max=4, kind="briarwolf")
    z.save()


def oakhaven():
    """Oakhaven Outpost, the town (maps/oakhaven.json, read by scripts/town.gd): spread out, with room between its people.
    A cobbled square in the middle with the campfire and the waypoint, dirt roads to each part: the west gate (the road
    to the Blackroot Wilds), the smith, the sage and the dyer in the west, the market and the shrine between the square
    and the river, a raised terrace in the north (up its stairs: the Battlemaster, the stash and the jeweler), and across
    the river by the bridge the Rift Gate and the captain. The NPCs and the exits are markers (town.gd makes them); the
    houses, lamps, trees and the rest are props. No monsters."""
    z = Zone("oakhaven", "Oakhaven Outpost", 40, 30, seed=7123, theme="woodland")
    spawn = (17, 21)
    plaza = (17, 17)
    z.border(2)
    z.smooth(1)
    z.clear((3, 17), 2)  # the west gate
    for c, r in [(plaza, 6), (spawn, 3), (( 8, 14), 3), ((8, 22), 3), ((12, 25), 3), ((26, 14), 3), ((25, 21), 3), ((25, 26), 3),
                 ((35, 15), 4), ((18, 7), 2), ((6, 18), 2)]:
        z.clear(c, r)
    # The river, edge to edge, with two bridges; the terrace in the north
    z.river([(29, 0), (29, 13), (31, 13), (31, 29)])
    z.bridge((31, 17))
    z.terrace((11, 3), 15, 8, stairs=[6, 7])  # footprint x 11..25, y 3..10; steps at (17, 10) and (18, 10)
    z.reachable_only(spawn)

    # Roads and paths: dirt between the parts of the town, cobblestone where people stand
    for a, b in [((3, 17), (13, 17)), ((20, 17), (30, 17)), ((32, 17), (34, 17)), ((34, 17), (35, 14)), ((17, 14), (17, 9)),
                 ((17, 20), (17, 21)), ((10, 17), (8, 14)), ((10, 17), (8, 22)), ((10, 22), (12, 25)), ((23, 17), (26, 14)),
                 ((22, 18), (25, 21)), ((22, 20), (25, 26)), ((17, 9), (13, 8)), ((17, 9), (23, 8)), ((29, 17), (31, 17))]:
        z.route(a, b, "d")
    z.plaza(plaza, 2)  # the square: 5 x 5 cobblestones, the rest dirt
    z.plaza((35, 14), 1)  # the Rift Gate
    z.plaza((3, 17), 1)  # the west gate
    z.lamps(every=5)

    # Markers: where the town's people stand and its exits (town.gd makes them)
    for name, c in [("spawn", spawn), ("west_exit", (3, 17)), ("waypoint", (22, 18)), ("tp", (14, 21)), ("gate", (35, 14)),
                    ("npc_blacksmith", (8, 14)), ("npc_dyer", (8, 22)), ("npc_sage", (12, 25)), ("npc_corwin", (7, 18)),
                    ("npc_merchant", (26, 14)), ("npc_gambler", (25, 21)), ("npc_althea", (25, 26)),
                    ("npc_stash", (18, 8)), ("npc_brom", (13, 8)), ("npc_jeweler", (23, 8)), ("npc_captain", (34, 17))]:
        z.add("marker", c, id=name)

    # The square: the fire, the banner, a signpost, lamps at the corners
    z.prop("desert/decor_7", plaza, scale=0.6)
    z.prop("decor_3", (15, 15), dx=0.3, scale=0.5)
    z.prop("decor_9", (19, 20), scale=0.5)
    z.prop("decor_10", (20, 15), dx=0.7, scale=0.42)
    for c in [(13, 14), (21, 14), (13, 20), (21, 20)]:
        z.prop("decor_4", c, dx=0.5, scale=0.45)
    # The north terrace: the stash keeper's house, the jeweler's cottage, the Battlemaster's banner and a woodpile
    z.prop("building_3", (18, 5), dy=0.95, scale=0.55, solid=True)
    z.prop("building_6", (23, 5), dy=0.95, scale=0.45, solid=True)
    z.prop("decor_3", (13, 6), dx=0.3, scale=0.5)
    z.prop("decor_8", (14, 5), dx=0.6, scale=0.42, solid=True)
    z.prop("decor_1", (16, 7), dx=0.5, scale=0.45)
    z.prop("decor_1", (20, 7), dx=0.5, scale=0.45)
    # The west: the smithy and its forge, a woodpile and rocks; the wagon by the gate road; the well and the pond
    z.prop("building_5", (7, 12), dy=0.95, scale=0.55, solid=True)
    z.prop("desert/decor_7", (10, 14), scale=0.45)
    z.prop("decor_8", (5, 13), dx=0.5, scale=0.42, solid=True)
    z.prop("stones_1", (5, 15), dx=0.5, scale=0.45)
    z.prop("desert/decor_8", (6, 19), dx=0.5, scale=0.45, solid=True)
    z.prop("decor_10", (8, 19), dx=0.3, scale=0.42)
    z.prop("decor_10", (10, 23), dx=0.5, scale=0.4)
    z.prop("building_7", (14, 26), dx=0.5, scale=0.5, solid=True)
    z.prop("desert/lake", (4, 25), scale=0.75)
    for dx, dy in [(-2, -1), (2, -1), (-1, 2), (3, 1)]:
        z.prop("tree_" + str(z.rng.choice([2, 3, 5, 9])), (4 + dx, 25 + dy), scale=0.55)
    # Between the square and the river: the merchant's house and stall, the gambler's tent, Althea's shrine of braziers
    z.prop("building_1", (26, 11), dy=0.95, scale=0.5, solid=True)
    z.prop("desert/decor_2", (23, 14), scale=0.42, solid=True)
    z.prop("decor_4", (28, 15), dx=0.5, scale=0.45)
    z.prop("desert/decor_2", (27, 22), scale=0.45, solid=True)
    z.prop("desert/decor_8", (23, 23), scale=0.42, solid=True)
    for dx, dy in [(-2, -1), (2, -1), (-2, 1), (2, 1)]:
        z.prop("decor_4", (25 + dx, 26 + dy), dx=0.5, scale=0.45)
    z.prop("stones_2", (25, 28), scale=0.5)
    # Across the river: the watchtower by the Rift Gate, and lamps
    z.prop("building_4", (37, 12), dy=0.95, scale=0.45, solid=True)
    z.prop("decor_4", (33, 15), dx=0.5, scale=0.45)
    z.prop("decor_4", (37, 16), dx=0.5, scale=0.45)
    # Boats on the river, a signpost at the bridge, a few trees and rocks on the open ground (room to walk, not a thicket)
    z.prop("decor_12", (29, 4), dx=0.5, dy=0.7, scale=0.4)
    z.prop("decor_12", (31, 24), dx=0.5, dy=0.7, scale=0.4)
    z.prop("decor_9", (32, 16), dx=0.4, scale=0.5)
    keep = [plaza, spawn, (8, 14), (8, 22), (12, 25), (26, 14), (25, 21), (25, 26), (35, 14), (3, 17), (18, 8), (13, 8), (23, 8),
            (7, 18), (22, 18), (14, 21), (34, 17), (4, 25), (7, 12), (26, 11), (37, 12)]
    placed = 0
    tries = 0
    while placed < 34 and tries < 4000:
        tries += 1
        c = (z.rng.randrange(3, z.cols - 3), z.rng.randrange(3, z.rows - 3))
        if not z.open_around(c, 1) or z.roads[c[1]][c[0]] != "." or z.water[c[1]][c[0]] != ".":
            continue
        if any(math.dist(c, k) < 5.5 for k in keep) or any(math.dist(c, (t["x"] // CELL, t["y"] // CELL)) < 1.2 for t in z.objects if t["type"] == "prop"):
            continue
        if any(t["type"] == "terrace" and t["x"] - 1 <= c[0] <= t["x"] + t["w"] and t["y"] - 1 <= c[1] <= t["y"] + t["h"] for t in z.objects):
            continue
        if z.rng.random() < 0.65:
            z.prop("tree_" + str(z.rng.choice([1, 2, 3, 4, 5, 6, 7, 8, 9, 10])), c, dx=z.rng.uniform(0.3, 0.7), dy=z.rng.uniform(0.6, 0.95), scale=0.6)
        else:
            z.prop("stones_" + str(z.rng.choice([1, 2, 3, 4, 5, 6])), c, dx=0.5, dy=0.8, scale=0.45)
        placed += 1
    z.add("start", spawn)
    z.save("special")


def weeping_hollow():
    """The Weeping Hollow (Act I, Chapter 2): limestone caves under the Blackroot Wilds, bioluminescent and wet, a tainted river
    through a wide gallery with two bridges, nests of skitterers and a mushroom grotto, and the Brood Cyst's great cavern in
    the north-east where Skittering Matron Vhol guards it. Theme "hollow" (stone-brick walls over void; tools/import_cave.py)."""
    z = Zone("weeping_hollow", "The Weeping Hollow", 60, 44, seed=3301, theme="hollow")
    z.fill()
    chambers = {"entry": ((6, 22), 4), "a": ((18, 22), 5), "b": ((14, 9), 4), "c": ((16, 36), 4),
                "d": ((46, 24), 5), "e": ((50, 10), 7), "f": ((50, 36), 4)}
    for c, r in chambers.values():
        z.clear(c, r)
    # The river gallery: a canyon down the middle, the river along it
    river_path = [(33, 2), (33, 16), (36, 16), (36, 41)]
    cells = []
    for a, b in zip(river_path, river_path[1:]):
        x, y = a
        while (x, y) != b:
            cells.append((x, y))
            x += (b[0] > x) - (b[0] < x)
            y += (b[1] > y) - (b[1] < y)
    cells.append(river_path[-1])
    for c in cells:
        z.clear(c, 3)
    # Tunnels between the chambers and out to the banks
    for a, b in [(chambers["entry"][0], chambers["a"][0]), (chambers["a"][0], chambers["b"][0]), (chambers["a"][0], chambers["c"][0]),
                 (chambers["a"][0], (30, 22)), ((40, 22), chambers["d"][0]), (chambers["b"][0], (30, 9)), ((38, 9), chambers["e"][0]),
                 (chambers["d"][0], chambers["e"][0]), (chambers["d"][0], chambers["f"][0]), ((30, 33), chambers["c"][0])]:
        z.road(a, b, 1)
    river = z.river(river_path)
    z.bridge_near(river, (36, 22), reach=2)
    z.bridge_near(river, (33, 9), reach=2)
    start = (6, 22)
    z.reachable_only(start)

    z.add("start", start)
    z.add("portal", (3, 22), target="dune_wastes")
    z.clear((3, 22), 1)
    z.add("waypoint", (19, 24))
    z.prop("decor_16", (16, 20), dx=0.5, scale=0.5, solid=True)  # a gargoyle on its plinth over the first cavern

    # The Brood Cyst: a fleshy mass anchored in the north-east cavern, its guardian beside it, and the ward to plant
    e = chambers["e"][0]
    z.add("trigger", e, radius=560, id="brood_cyst", text="The water here runs black. Something vast pulses in the dark ahead.")
    for dx, dy, sp, sc in [(2, -3, "greenery_8", 1.5), (4, -2, "greenery_9", 1.3), (3, -4, "greenery_10", 1.2), (5, -4, "greenery_8", 1.0)]:
        z.prop(sp, (e[0] + dx, e[1] + dy), scale=sc, solid=True)
    z.prop("crystal_2", (e[0] + 3, e[1] - 2), scale=0.7)
    z.add("boss", (e[0], e[1] + 1), id="matron_vhol", name="Skittering Matron Vhol", kind="blind_crawler", skin="ghoul", hp=12.0, size=1.9)
    z.add("quest_object", (e[0] - 2, e[1] + 3), id="purge_ward", sprite="", prompt="Plant the Alchemical Purge Ward",
          text="You set the ward in the cyst's wake. The water clears for a moment, then the dead mass bursts, and its blood runs "
               "into the stone and screams: whispers, from the north, from the ancestral tombs.")
    for dx, dy in [(-4, -2), (-5, 2), (4, 4)]:
        z.prop("bone_" + str(z.rng.choice([1, 4, 5, 6])), (e[0] + dx, e[1] + dy), scale=0.5)
    z.prop("decor_11", (e[0] - 3, e[1] - 4), scale=0.55)  # a spider in its web
    z.prop("decor_10", (e[0] - 3, e[1] - 3), scale=0.6)

    # Spider nest B, the mushroom grotto C, the bank of the gallery: webs, bones, mushrooms, crystals
    b = chambers["b"][0]
    z.prop("decor_10", (b[0] - 1, b[1] - 2), scale=0.6)
    z.prop("decor_11", (b[0] - 1, b[1] - 2), dx=0.4, dy=0.7, scale=0.5)
    for dx, dy in [(2, 1), (-2, 2), (1, -2)]:
        z.prop("bone_" + str(z.rng.choice([2, 8, 9, 10])), (b[0] + dx, b[1] + dy), scale=0.5)
    c_ = chambers["c"][0]
    for dx, dy in [(-2, -1), (2, -1), (0, 2), (-3, 1)]:
        z.prop("greenery_1" if (dx + dy) % 2 else "greenery_2", (c_[0] + dx, c_[1] + dy), scale=0.7, solid=False)
    z.prop("crystal_7", (c_[0] + 1, c_[1] - 2), scale=0.6)
    d = chambers["d"][0]
    z.prop("crystal_5", (d[0] - 2, d[1] - 1), scale=0.6)
    z.prop("crystal_10", (d[0] + 2, d[1] + 1), scale=0.6)
    f = chambers["f"][0]
    verge_exit = z.exit_near("ashen_verge", (f[0] + 4, f[1]))  # the vine-choked iron gate: the way on to the Ashen Verge
    z.prop("decor_13", (verge_exit[0], verge_exit[1] - 1), dx=0.5, dy=0.95, scale=0.5)
    z.prop("decor_6", (f[0] + 2, f[1] + 1), scale=0.4)

    themes = [(b, 7, "cave_skitterer"), (c_, 6, "blind_crawler"), (d, 6, "ghoul"), (chambers["a"][0], 6, "blind_crawler")]
    avoid = [(start, 7), ((19, 24), 4), (e, 9), ((3, 22), 3)]
    z.packs(26, avoid, themes, min_gap=6, start=start, min_start=8)
    z.save("story")


def sunken_fen():
    """The Sunken Fen (Act I): drowned woodland south of the Blackroot Wilds. Wide stretches of mire that slow you and the things
    that hunt you, dead trees, rot-bloat zombies, leechfiends and Fen Crawlers, and the apothecary Voss in a stone hovel at the
    far side (A Taste for Rot). A road out of its east edge leads on to the Ashen Verge."""
    z = Zone("sunken_fen", "Sunken Fen", 60, 44, seed=4417, theme="woodland")
    start = (30, 4)
    voss = (50, 34)
    waypoint = (28, 8)
    z.outcrops(60, 1.5, 3.5)
    z.border(2)
    z.smooth(2)
    for c, r in [(start, 4), (waypoint, 3), (voss, 5), ((10, 34), 4), ((12, 14), 4), ((50, 12), 4)]:
        z.clear(c, r)
    z.road(start, waypoint, 1)
    z.road(waypoint, (12, 14), 1)
    z.road(waypoint, (50, 12), 1)
    z.road(waypoint, (30, 24), 1)
    z.road((30, 24), voss, 1)
    z.road((30, 24), (10, 34), 1)
    z.reachable_only(start)
    verge_exit = z.exit_near("ashen_verge", (56, 20))
    # The dry way: a dirt road to each part, and mire (slow ground) over the rest of the low places
    for a_, b_ in [(start, waypoint), (waypoint, (12, 14)), (waypoint, (50, 12)), (waypoint, (30, 24)), ((30, 24), voss), ((30, 24), (10, 34)),
                   ((50, 12), verge_exit)]:
        z.route(a_, b_, "d")
    z.lamps(every=7)
    for c in [(20, 22), (40, 20), (24, 34), (42, 40), (14, 26), (36, 30), (22, 10), (46, 24), (8, 40)]:
        z.mire(c, z.rng.randint(3, 5))
    z.add("start", start)
    z.add("portal", (start[0], 2), target="dune_wastes")
    z.clear((start[0], 2), 1)
    z.add("waypoint", waypoint)
    z.prop("decor_9", (start[0] + 2, start[1] + 1), scale=0.5)
    # The hovel: a stone hut with a log roof, a cauldron's smoke of lamps and bottles, and Voss
    z.prop("hollow/decor_17", (voss[0], voss[1] - 3), dy=0.95, scale=0.5, solid=True)
    z.prop("decor_10", (voss[0] - 3, voss[1] - 1), scale=0.45, solid=True)
    z.prop("decor_10", (voss[0] + 3, voss[1] - 1), scale=0.45, solid=True)
    z.prop("hollow/decor_8", (voss[0] - 2, voss[1] + 1), scale=0.5)
    z.prop("decor_4", (voss[0] + 2, voss[1] + 1), scale=0.45)
    z.add("npc", (voss[0], voss[1] - 1), id="voss", facing=-1)
    z.add("trigger", voss, radius=420, id="voss_hovel", text="A stone hovel half sunk in the mire. Smoke, and a smell of something boiled too long.")
    # Dead trees, stumps and the odd bloom on the dry ground; the paths on are choked with thorns
    for _ in range(46):
        c = (z.rng.randrange(3, z.cols - 3), z.rng.randrange(3, z.rows - 3))
        if z.open_around(c, 1) and math.dist(c, start) > 5 and math.dist(c, voss) > 5 and math.dist(c, waypoint) > 3:
            z.prop("tree_" + str(z.rng.choice([11, 12, 11, 12, 13, 14, 5])), c, dx=z.rng.uniform(0.3, 0.7), dy=z.rng.uniform(0.6, 0.95), scale=0.62)
    z.prop("decor_9", (verge_exit[0] - 1, verge_exit[1] - 1), scale=0.5)  # a signpost where the road leaves the Fen
    z.prop("tree_12", (verge_exit[0] - 1, verge_exit[1] + 2), scale=0.7)
    themes = [(voss, 9, "fen_crawler"), ((24, 34), 8, "leechfiend"), ((40, 20), 8, "rot_bloat"), ((12, 14), 7, "fen_crawler"),
              ((10, 34), 7, "rot_bloat")]
    avoid = [(start, 8), (waypoint, 4), (voss, 4)]
    z.packs(28, avoid, themes, min_gap=6, start=start, min_start=9)
    z.save("story")


def ashen_verge():
    """The Ashen Verge (Act I, Chapter 3: Breaking the Seal): the autumn woods burnt out, petrified trees and desecrated headstones,
    active Bleed Rifts spawning armoured fiends, and outer ruins. Two ways in (from the Weeping Hollow and the Sunken Fen) in the
    west; a graveyard in the north where the Maddened Grave Warden holds half the Warded Keystone; a Bleed Rift in the south where
    the Rift Golem holds the other half; a watchtower in the south-east where the last scout holds out (The Last Watch); and on
    raised ground in the east, up stairs, the sealed mausoleum: the Ossuary's iron gates, opened with the joined keystone.
    Theme "ashen": the woodland art burnt dark."""
    z = Zone("ashen_verge", "Ashen Verge", 72, 48, seed=5519, theme="ashen")
    start = (8, 25)
    waypoint = (16, 25)
    grave = (33, 12)
    chapel = (52, 9)
    rift = (31, 37)
    tower = (49, 39)
    s1, s2 = (21, 9), (19, 41)  # the two mutated scouts
    foot = (62, 31)  # the foot of the mausoleum's stairs
    hollow_gate, fen_gate = (5, 17), (5, 33)
    terr = (56, 19, 12, 10)  # x, y, w, h: the mausoleum's raised ground
    minor_rifts = [(42, 26), (24, 24), (59, 41)]
    paths = [(start, waypoint), (start, hollow_gate), (start, fen_gate), (waypoint, grave), (waypoint, rift), (grave, chapel),
             (grave, rift), (rift, tower), (chapel, foot), (tower, foot), (grave, s1), (rift, s2), (waypoint, minor_rifts[1]),
             (minor_rifts[0], foot), (tower, minor_rifts[2])]

    z.outcrops(70, 1.5, 4.0)
    z.border(2)
    z.smooth(2)
    for c, r in [(start, 4), (waypoint, 3), (grave, 7), (chapel, 5), (rift, 8), (tower, 5), (s1, 2), (s2, 2), (foot, 3),
                 (hollow_gate, 2), (fen_gate, 2), ((terr[0] + 6, terr[1] + 5), 8)] + [(c, 2) for c in minor_rifts]:
        z.clear(c, r)
    for a, b in paths:
        z.road(a, b, 1)
    z.terrace((terr[0], terr[1]), terr[2], terr[3], [5, 6], tree_ids=[11, 12])
    z.reachable_only(start)

    hollow_exit = z.exit_near("weeping_hollow", (3, 17))
    fen_exit = z.exit_near("sunken_fen", (3, 33))
    # Ash roads: dirt, with cobblestone at the places that matter
    for a, b in paths:
        z.route(a if a != hollow_gate else a, hollow_exit if b == hollow_gate else (fen_exit if b == fen_gate else b), "d")
    z.plaza(waypoint, 1)
    z.plaza(foot, 1)
    z.plaza((tower[0], tower[1] + 1), 1)
    z.lamps(every=9)

    z.add("start", start)
    z.add("waypoint", waypoint)
    z.prop("decor_9", (start[0] + 2, start[1] - 2), scale=0.5)  # signpost where the roads from the Hollow and the Fen meet
    z.prop("decor_4", (waypoint[0] - 1, waypoint[1] - 1), dx=0.3, scale=0.45)
    z.prop("decor_4", (waypoint[0] + 1, waypoint[1] + 1), dx=0.7, scale=0.45)
    z.prop("tree_12", (hollow_exit[0] + 1, hollow_exit[1] + 1), scale=0.7)
    z.prop("tree_11", (fen_exit[0] + 1, fen_exit[1] - 1), scale=0.7)

    # The graveyard: rows of split headstones and rune stones, dead branches, and the warden among them, holding half the keystone
    z.add("trigger", grave, radius=560, id="grave_field", text="A graveyard, its headstones split and sooty. Something among them is digging.")
    for dy in (-4, -2, 2, 4):
        for dx in range(-6, 7, 2):
            c = (grave[0] + dx + (1 if dy % 4 == 0 else 0), grave[1] + dy)
            if z.open_around(c, 0) and math.dist(c, grave) > 2.5:
                z.prop("crypt/decor_1", c, dx=z.rng.uniform(0.3, 0.7), dy=z.rng.uniform(0.7, 0.95), scale=0.28)
    for dx, dy in [(-5, 0), (5, 1), (0, -6), (-3, 5)]:
        z.prop("hollow/rune_" + str(z.rng.choice([1, 2, 3, 4, 5, 6, 7])), (grave[0] + dx, grave[1] + dy), scale=0.45)
    for dx, dy in [(-4, -3), (4, -3), (3, 4), (-2, 3)]:
        z.prop("crypt/decor_14", (grave[0] + dx, grave[1] + dy), scale=0.5)
    z.prop("decor_8", (grave[0] + 7, grave[1] - 2), scale=0.45, solid=True)  # the warden's woodpile
    z.add("boss", (grave[0], grave[1] + 1), id="grave_warden", name="The Maddened Grave Warden", kind="zombie",
          skin="zombie_villager_3", hp=10.0, size=1.7)
    z.add("quest_object", (grave[0] + 2, grave[1] + 2), id="warden_half", sprite="crypt/decor_34", scale=0.6,
          prompt="Take the first half of the Warded Keystone",
          text="You take the first half of the Warded Keystone from the warden's fist. It is carved with a stair going down, and it is warm.")

    # The outer ruins: a roofless chapel, broken walls
    z.add("trigger", chapel, radius=420, id="outer_ruins", text="The outer ruins: a chapel of the old Oakhaven, roofless and sooted black.")
    z.prop("hollow/decor_20", (chapel[0], chapel[1] - 2), dy=0.95, scale=0.55, solid=True)
    z.prop("crypt/decor_12", (chapel[0] - 5, chapel[1] - 1), dy=0.95, scale=0.4, solid=True)
    z.prop("crypt/decor_11", (chapel[0] + 5, chapel[1] - 1), dy=0.95, scale=0.4, solid=True)
    z.prop("hollow/decor_14", (chapel[0] - 2, chapel[1] + 2), scale=0.5)
    z.prop("hollow/decor_15", (chapel[0] + 2, chapel[1] + 2), scale=0.5)
    z.prop("tree_12", (chapel[0] - 6, chapel[1] + 2), scale=0.7)

    # Bleed Rifts: a ring of crystals and horns round a tear in the air; the big one in the south holds the golem
    def rift_site(c, big):
        n = 8 if big else 5
        for i in range(n):
            ang = i * math.tau / n
            rc = (round(c[0] + math.cos(ang) * (3.2 if big else 2.0)), round(c[1] + math.sin(ang) * (2.6 if big else 1.6)))
            if z.open_around(rc, 0):
                z.prop("crypt/rift_" + str(z.rng.choice([1, 2, 3])), rc, dy=0.8, scale=0.6 if big else 0.5)
        z.prop("hollow/decor_4", c, dy=0.95, scale=0.7 if big else 0.5)
        z.prop("crypt/blood_" + str(z.rng.choice([1, 2, 3])), (c[0], c[1] + 1), scale=0.9 if big else 0.6)
    rift_site(rift, True)
    for c in minor_rifts:
        rift_site(c, False)
        z.add("pack", c, min=3, max=4, kind="bleed_fiend")
    z.add("trigger", rift, radius=600, id="bleed_rift", text="A Bleed Rift, a wound in the air that bleeds red light. Something lumbers inside it.")
    z.add("boss", (rift[0], rift[1] + 1), id="rift_golem", name="The Rift Golem", kind="rot_bloat", skin="golem", hp=12.0, size=2.0)
    z.add("quest_object", (rift[0] + 3, rift[1] + 3), id="golem_half", sprite="crypt/decor_34", scale=0.6,
          prompt="Take the second half of the Warded Keystone",
          text="You pull the second half of the Warded Keystone from the golem's broken chest. It fits the first one's edge as a key fits a lock.")

    # The watchtower: the last scout holds out inside its barricade (The Last Watch)
    z.add("trigger", tower, radius=420, id="last_watch_tower", text="A watchtower, its beacon cold. Someone has barricaded the door from inside.")
    z.prop("building_4", (tower[0], tower[1] - 2), dy=0.95, scale=0.5, solid=True)
    for dx, dy in [(-3, 0), (3, 0), (0, 2)]:
        z.prop("decor_15", (tower[0] + dx, tower[1] + dy), scale=0.45, solid=True)
    z.prop("decor_4", (tower[0] - 1, tower[1] + 1), dx=0.2, scale=0.45)
    z.prop("desert/decor_6", (tower[0] + 2, tower[1] + 2), scale=0.4)
    z.add("npc", (tower[0], tower[1] + 1), id="mara", facing=-1)
    for c in (s1, s2):  # the scouts the Taint twisted
        z.add("pack", c, min=1, max=1, kind="mutated_scout")
        z.prop("desert/decor_6", (c[0] + 1, c[1] + 1), scale=0.4)
        z.prop("decor_6", (c[0] - 1, c[1] + 1), scale=0.45)

    # The sealed mausoleum on the raised ground: the Ossuary's gates, flanked by gargoyles, and the plinth for the keystone
    tx, ty, tw, th = terr
    mid = tx + tw // 2
    z.add("trigger", (mid, ty + 5), radius=480, id="mausoleum", text="The Ossuary's iron gates: sealed in two pieces. Before them, a plinth shaped for a keystone.")
    z.prop("hollow/decor_19", (mid - 2, ty + 3), dy=0.95, scale=0.7, solid=True)
    z.prop("hollow/decor_16", (mid - 4, ty + 4), scale=0.4, solid=True)
    z.prop("hollow/decor_16", (mid + 3, ty + 4), scale=0.4, solid=True)
    z.prop("hollow/decor_13", (mid + 2, ty + 3), dx=0.5, dy=0.95, scale=0.4, solid=True)
    z.add("portal", (mid, ty + 3), target="grand_ossuary_1", requires="a1_breaking_the_seal")  # the iron gates: open once the seal is broken
    z.prop("decor_4", (mid - 2, ty + 6), dx=0.5, scale=0.45)
    z.prop("decor_4", (mid + 2, ty + 6), dx=0.5, scale=0.45)
    z.prop("crypt/decor_14", (mid - 3, ty + 7), scale=0.5)
    z.add("quest_object", (mid, ty + 6), id="mausoleum_seal", sprite="hollow/rune_1", scale=0.6, prompt="Join the halves of the Warded Keystone",
          text="You set the two halves into the plinth, and they meet with a sound like a bell. The seal on the Ossuary's gates cracks "
               "and falls away, and the iron swings inward onto a stair into the dark. The whispers are loud now.")

    themes = [(grave, 9, "skeleton"), (chapel, 7, "ghoul"), (rift, 9, "bleed_fiend"), (tower, 7, "skeleton_warrior")]
    avoid = [(start, 9), (waypoint, 4), (grave, 3), (rift, 3), (tower, 3), (foot, 3), ((mid, ty + 5), 7), (s1, 3), (s2, 3),
             (hollow_exit, 4), (fen_exit, 4)]
    z.packs(30, avoid, themes, min_gap=7, start=start, min_start=9)
    z.save("story")


def _hall_props(z, hall):
    x0, y0, x1, y1 = hall
    for x in range(x0 + 2, x1 - 1, 4):
        z.prop("torch_1", (x, y0), dx=0.5, dy=0.35, scale=0.5)


def _pillars(z, hall, keep, step=4):
    """Single-cell pillars on a lattice inside a hall (wall islands), clear of the `keep` cells and the corridors' mouths."""
    x0, y0, x1, y1 = hall
    for y in range(y0 + 2, y1 - 1, step):
        for x in range(x0 + 2, x1 - 1, step):
            if all(math.dist((x, y), k) > 2.6 for k in keep):
                z.wall[y][x] = True


def _trap_row(z, trail, frac):
    """Spike traps across a hallway where it runs straight: all but one of the cells across it (the safe lane is random)."""
    i = int(len(trail) * frac)
    while 0 < i < len(trail) - 1 and trail[i - 1][0] != trail[i + 1][0] and trail[i - 1][1] != trail[i + 1][1]:
        i += 1  # not on a bend
    if not 0 < i < len(trail) - 1:
        return
    c = trail[i]
    horizontal = trail[i + 1][1] == trail[i][1]
    cells = [(c[0], c[1] + d) if horizontal else (c[0] + d, c[1]) for d in (-1, 0, 1)]
    safe = z.rng.randrange(3)
    for k, cell in enumerate(cells):
        if k != safe and not z.wall[cell[1]][cell[0]]:
            z.add("trap", cell)


def _lanterns(z, trail, every=7, offset=1):
    for i in range(3, len(trail) - 2, every):
        c = trail[i]
        horizontal = trail[i + 1][1] == trail[i][1]
        cell = (c[0], c[1] - offset) if horizontal else (c[0] - offset, c[1])
        if 1 <= cell[0] < z.cols - 1 and 1 <= cell[1] < z.rows - 1 and not z.wall[cell[1]][cell[0]]:
            z.prop("lantern_1", cell, dx=0.5, dy=0.85, scale=0.42)


def _mid(h):
    return ((h[0] + h[2]) // 2, (h[1] + h[3]) // 2)


def _litter(z, halls, per=16):
    """Walk-through clutter on the floor of the halls: broken branches, bones, stones, urns, barrels, spilled blood."""
    keep = [(o["x"] / CELL, o["y"] / CELL) for o in z.objects if o["type"] in ("quest_object", "npc", "boss", "portal", "waypoint", "vault")]
    things = [("crypt/decor_14", 0.5), ("crypt/decor_15", 0.5), ("stones_9", 0.5), ("stones_10", 0.5), ("hollow/bone_2", 0.5),
              ("hollow/bone_9", 0.5), ("hollow/bone_10", 0.5), ("hollow/bone_7", 0.5), ("decor_4", 0.45), ("decor_2", 0.45), ("crypt/blood_1", 0.3), ("crypt/blood_3", 0.3),
              ("stones_5", 0.45), ("decor_14", 0.5)]
    for h in halls:
        n = max(3, (h[2] - h[0]) * (h[3] - h[1]) // per)
        for _ in range(n):
            c = (z.rng.randint(h[0] + 1, h[2] - 1), z.rng.randint(h[1] + 1, h[3] - 1))
            if z.open_around(c, 0) and all(math.dist(c, k) > 2.0 for k in keep):
                sprite, sc = z.rng.choice(things)
                z.prop(sprite, c, dx=z.rng.uniform(0.2, 0.8), dy=z.rng.uniform(0.3, 0.9), scale=sc)


def _anchor_ring(z, c, scale=0.5):
    for i in range(8):
        ang = i * math.tau / 8
        rc = (round(c[0] + math.cos(ang) * 3.0), round(c[1] + math.sin(ang) * 2.4))
        if z.open_around(rc, 0):
            z.prop("crypt/rift_" + str(z.rng.choice([1, 2, 3])), rc, dx=0.5, dy=0.9, scale=scale + z.rng.random() * 0.3)
    for dx, dy in [(-2, 1), (2, 1), (0, 2)]:
        z.prop("crypt/blood_" + str(z.rng.choice([1, 2, 3])), (c[0] + dx, c[1] + dy), scale=0.5)


def grand_ossuary_1():
    """The Grand Ossuary, level 1 (Act I, Chapter 4: Descent into Madness): narrow stone halls and sarcophagi under the Ashen Verge.
    The way in is a gatehall in the west; the guardroom beyond has the waypoint, the weeping spirit of Restless Ancestors and
    the cracked wall of the armory vault; two tomb-halls (north and south) hold the four desecrated urns; the charnel hall in the
    north-east and the lower ossuary in the south-east each hold a Veil Anchor and the herald who channels it; spike traps in the
    hallways; the stair down to the Lower Ossuary in the far east. Theme "crypt"."""
    z = Zone("grand_ossuary_1", "The Grand Ossuary", 66, 46, seed=6601, theme="crypt")
    z.fill()
    gate, guard = (3, 20, 10, 26), (15, 17, 29, 29)
    tomb_a, tomb_b = (8, 3, 21, 12), (8, 34, 21, 43)
    cross, charnel, ossuary, stair = (35, 19, 45, 27), (34, 3, 47, 13), (34, 33, 47, 43), (54, 18, 62, 28)
    for h in (gate, guard, tomb_a, tomb_b, cross, charnel, ossuary, stair):
        z.hall(*h)
    mid = _mid
    start, wp = (6, 23), (19, 23)
    trails = {}
    trails["gate"] = z.hallway(mid(gate), mid(guard), 3)
    trails["a"] = z.hallway(mid(guard), mid(tomb_a), 3, first="x")
    trails["b"] = z.hallway(mid(guard), mid(tomb_b), 3, first="x")
    trails["cross"] = z.hallway(mid(guard), mid(cross), 3)
    trails["c"] = z.hallway(mid(cross), mid(charnel), 3)
    trails["d"] = z.hallway(mid(cross), mid(ossuary), 3)
    trails["f"] = z.hallway(mid(cross), mid(stair), 3)
    trails["cf"] = z.hallway((47, 8), (58, 8), 2)
    trails["cf2"] = z.hallway((58, 8), mid(stair), 2, first="y")
    trails["df"] = z.hallway((47, 38), (58, 38), 2)
    trails["df2"] = z.hallway((58, 38), mid(stair), 2, first="y")
    oren, sable = mid(charnel), mid(ossuary)
    anchor1, anchor2 = (oren[0], oren[1] - 4), (sable[0], sable[1] + 4)
    spirit, pedestal, vault = (25, 21), (26, 25), (23, 17)
    for h, keep in [(guard, [wp, spirit, pedestal, vault, mid(guard)]), (cross, [mid(cross)]), (charnel, [oren, anchor1]), (ossuary, [sable, anchor2])]:
        edge = [(h[0], mid(h)[1]), (h[2], mid(h)[1]), (mid(h)[0], h[1]), (mid(h)[0], h[3])]
        _pillars(z, h, keep + edge)
    z.reachable_only(start)

    z.add("start", start)
    z.add("portal", (4, 23), target="ashen_verge")
    z.add("waypoint", wp)
    z.add("trigger", (7, 23), radius=520, id="ossuary_gate", text="The Grand Ossuary. The air is cold and tastes of old stone, and the whispering is all around you.")
    for x in range(gate[0] + 2, gate[2], 3):
        z.prop("lantern_1", (x, gate[1]), dx=0.5, dy=0.35, scale=0.45)
    z.prop("crypt/decor_13", (3, 22), dx=0.3, dy=0.95, scale=0.5)  # the stair's iron gate, standing open behind the portal
    z.prop("decor_7", (8, 21), scale=0.4)

    for h in (guard, cross, charnel, ossuary, stair, tomb_a, tomb_b):
        _hall_props(z, h)
    for key in ("gate", "a", "b", "cross", "c", "d", "f"):
        _lanterns(z, trails[key])
    for key, frac in [("c", 0.55), ("d", 0.55), ("f", 0.4), ("f", 0.75), ("cf", 0.5), ("df", 0.5), ("cross", 0.55)]:
        _trap_row(z, trails[key], frac)

    # The guardroom: the weeping spirit and her pedestal, and the armory vault behind a cracked wall
    z.add("npc", spirit, id="ancestor_spirit", name="Weeping Spirit", facing=1.0)
    z.add("quest_object", pedestal, id="urn_pedestal", sprite="crypt/decor_22", scale=0.5, prompt="Set the urns on the pedestal",
          text="You set the four urns on their pedestal, one after the other. The weeping stops. The air is warmer, if only for a moment.")
    z.add("vault", vault, dy=0.15, id="armory", sprite="crypt/decor_20", scale=0.95, requires="a1_the_last_watch",
          prompt="Press the cracked wall",
          locked="The wall is cracked, and cold air breathes through it. Behind it, an iron door: a lock the size of a fist. You have nothing that opens it.",
          text="The rusted key turns, and the wall gives way. The armory vault, sealed since the Ossuary was shut: racks of old steel, still good.",
          rares=3)
    z.prop("decor_2", (guard[0] + 2, guard[1] + 1), scale=0.5, solid=True)
    z.prop("decor_2", (guard[0] + 3, guard[1] + 1), dx=0.6, scale=0.5, solid=True)
    z.prop("decor_17", (guard[2] - 2, guard[1] + 1), scale=0.5, solid=True)
    z.prop("crypt/decor_14", (21, 27), scale=0.5)
    z.prop("hollow/bone_4", (27, 27), scale=0.5)

    # The tomb-halls: rows of sarcophagi, four of them opened and robbed of their urns
    def tombs(h, urn_cells, tag):
        x0, y0, x1, y1 = h
        for x in range(x0 + 2, x1 - 1, 4):
            for y in (y0 + 2, y1 - 2):
                z.prop("decor_22" if (x + y) % 8 else "decor_20", (x, y), dy=0.9, scale=0.55, solid=True)
        for i, c in enumerate(urn_cells):
            z.add("quest_object", c, id="urn_%s%d" % (tag, i + 1), key="urn", sprite="crypt/decor_4", scale=0.5, prompt="Take the desecrated urn",
                  text="You lift the urn out of the broken sarcophagus. It is cold and very light, and something inside it sighs.")
            z.prop("hollow/bone_" + str(z.rng.choice([2, 8, 9, 10])), (c[0] - 1, c[1]), scale=0.5)
        z.add("trigger", mid(h), radius=600, id="tomb_hall_" + tag, text="A tomb-hall: the sarcophagi are open and emptied of their urns.")
    tombs(tomb_a, [(11, 5), (17, 10)], "a")
    tombs(tomb_b, [(11, 41), (17, 36)], "b")
    for h in (tomb_a, tomb_b):
        for x in range(h[0] + 3, h[2] - 1, 4):
            if z.rng.random() < 0.5:
                z.prop("crypt/blood_" + str(z.rng.choice([1, 2, 3])), (x, mid(h)[1]), scale=0.35)

    # The Veil Anchors: a spire of the red crystal driven into the floor, a ring of blood about it, its herald before it
    def anchor_site(c, herald_at, aid, boss, name, skin, ambush, text):
        _anchor_ring(z, c, 0.85)
        z.add("boss", herald_at, id=boss, name=name, kind="dark_elf", skin=skin, hp=7.0, size=1.45)
        z.add("quest_object", c, id=aid, sprite="crypt/rift_2", scale=1.05, prompt="Shatter the Veil Anchor", text=text, ambush=ambush)
    anchor_site(anchor1, oren, "anchor_1", "herald_oren", "Herald Oren", "dark_elf_1", {"kind": "skeleton_vanguard", "n": 5},
                "The anchor cracks from its crown to its root and goes out. The floor heaves. Out of the dark, all round you, the vanguard rises.")
    anchor_site(anchor2, sable, "anchor_2", "herald_sable", "Herald Sable", "dark_elf_2", {"kind": "veil_cultist", "n": 5},
                "The second anchor shatters, and the whole hall lurches. The cult comes for you out of the shadows, hands already raised.")
    z.add("trigger", oren, radius=640, id="charnel_hall", text="A charnel hall, heaped with bones. At its end, a red spire hums in the floor, and a robed figure kneels before it.")
    z.add("trigger", sable, radius=640, id="lower_ossuary", text="Another anchor, and another herald. The floor is warm underfoot.")
    z.prop("hollow/bone_1", (oren[0] - 4, oren[1] + 1), scale=0.6)
    z.prop("hollow/bone_5", (oren[0] + 4, oren[1] - 1), scale=0.6)
    z.prop("hollow/bone_6", (sable[0] + 4, sable[1] + 1), scale=0.6)
    z.prop("hollow/bone_4", (sable[0] - 4, sable[1] - 1), scale=0.6)

    # The stair down
    sc = mid(stair)
    z.add("portal", (sc[0] + 2, sc[1]), target="grand_ossuary_2")
    z.add("trigger", sc, radius=520, id="ossuary_stair", text="A stair winds down into a deeper dark. The whispering comes up it like heat.")
    z.prop("crypt/decor_13", (sc[0] + 4, sc[1]), dx=0.7, dy=0.95, scale=0.5)
    for dy in (-3, 3):
        z.prop("lantern_1", (sc[0] + 2, sc[1] + dy), dy=0.9, scale=0.5)

    _litter(z, [gate, guard, tomb_a, tomb_b, cross, charnel, ossuary, stair])
    themes = [(mid(tomb_a), 8, "skeleton"), (mid(tomb_b), 8, "skeleton_warrior"), (mid(cross), 6, "skeleton_vanguard"),
              (oren, 7, "veil_cultist"), (sable, 7, "veil_cultist"), (sc, 6, "skeleton_archer")]
    avoid = [(start, 8), (wp, 4), (spirit, 3), (oren, 6), (sable, 6), ((4, 23), 3), ((sc[0] + 2, sc[1]), 3), (vault, 3)]
    z.packs(34, avoid, themes, min_gap=6, start=start, min_start=9)
    z.save("story")


def grand_ossuary_2():
    """The Lower Ossuary (the Grand Ossuary, level 2): older halls, deeper and colder. The stair down arrives in the north-west;
    a hall of bones with the waypoint; a cell-block to the south-west; a great nave in the north-east; and the choir in the
    south-east, where the third Veil Anchor stands and Herald Morrow channels it, and past it the great door to the Sepulcher of
    Mourning, barred for now. Theme "crypt"."""
    z = Zone("grand_ossuary_2", "The Lower Ossuary", 60, 46, seed=6602, theme="crypt")
    z.fill()
    arrive, bones, cells = (3, 4, 10, 10), (15, 15, 31, 29), (5, 30, 16, 41)
    nave, choir, apse = (35, 4, 55, 19), (37, 27, 55, 42), (56, 32, 58, 38)
    for h in (arrive, bones, cells, nave, choir, apse):
        z.hall(*h)
    mid = _mid
    start, wp = (6, 7), (22, 22)
    trails = {}
    trails["in"] = z.hallway(mid(arrive), (24, 7), 3)
    trails["in2"] = z.hallway((24, 7), mid(bones), 3, first="y")
    trails["cells"] = z.hallway(mid(bones), mid(cells), 3)
    trails["nave"] = z.hallway(mid(bones), mid(nave), 3)
    trails["choir"] = z.hallway(mid(bones), mid(choir), 3)
    trails["link"] = z.hallway((52, 19), (52, 27), 2, first="y")
    trails["apse"] = z.hallway(mid(choir), mid(apse), 3)
    morrow = (mid(choir)[0] - 3, mid(choir)[1] - 1)
    anchor3 = (mid(choir)[0] + 4, mid(choir)[1] + 1)
    for h, keep in [(bones, [wp, mid(bones)]), (nave, [mid(nave)]), (choir, [morrow, anchor3, mid(choir)]), (cells, [mid(cells)])]:
        edge = [(h[0], mid(h)[1]), (h[2], mid(h)[1]), (mid(h)[0], h[1]), (mid(h)[0], h[3]), (52, 19), (52, 27)]
        _pillars(z, h, keep + edge)
    z.reachable_only(start)

    z.add("start", start)
    z.add("portal", (4, 7), target="grand_ossuary_1")
    z.add("waypoint", wp)
    z.add("trigger", (7, 7), radius=520, id="lower_ossuary_arrive", text="The Lower Ossuary. The stone here is older, and the whispering has a voice in it.")
    for h in (arrive, bones, cells, nave, choir):
        _hall_props(z, h)
    for key in ("in", "in2", "cells", "nave", "choir", "apse"):
        _lanterns(z, trails[key])
    for key, frac in [("in2", 0.5), ("nave", 0.5), ("choir", 0.4), ("choir", 0.75), ("link", 0.5), ("cells", 0.55), ("apse", 0.5)]:
        _trap_row(z, trails[key], frac)

    # The hall of bones
    bc = mid(bones)
    for dx, dy in [(-5, -4), (5, -3), (-4, 4), (6, 4), (0, -5), (0, 5), (-7, 0)]:
        z.prop("hollow/bone_" + str(z.rng.choice([1, 4, 5, 6])), (bc[0] + dx, bc[1] + dy), scale=0.7)
    for dx, dy in [(-3, 1), (3, -1), (2, 4)]:
        z.prop("crypt/blood_" + str(z.rng.choice([1, 2, 3])), (bc[0] + dx, bc[1] + dy), scale=0.4)
    # The cell-block
    cx, cy = mid(cells)
    for dx in (-4, 0, 4):
        z.prop("decor_2", (cx + dx, cells[1] + 1), scale=0.5, solid=True)
        z.prop("hollow/bone_" + str(z.rng.choice([2, 8, 9, 10])), (cx + dx, cy + 2), scale=0.5)
    z.prop("decor_19", (cells[2] - 1, cells[3] - 1), dy=0.9, scale=0.5, solid=True)
    # The nave: sarcophagi in rows
    for y in (nave[1] + 3, nave[3] - 3):
        for x in range(nave[0] + 3, nave[2] - 2, 4):
            z.prop("decor_22" if (x + y) % 8 else "decor_20", (x, y), dy=0.9, scale=0.55, solid=True)
    z.add("trigger", mid(nave), radius=700, id="nave", text="The nave: row upon row of sarcophagi, every lid slid aside.")

    # The choir and the third Veil Anchor
    _anchor_ring(z, anchor3, 0.9)
    z.add("boss", morrow, id="herald_morrow", name="Herald Morrow", kind="dark_elf", skin="lich", hp=7.5, size=1.55)
    z.add("quest_object", anchor3, id="anchor_3", sprite="crypt/rift_2", scale=1.15, prompt="Shatter the Veil Anchor",
          text="The last anchor breaks, and a sound goes through the stone like a bell tolling under the world. The wall between the realms shudders and holds, for now. Ash falls from the ceiling.",
          ambush={"kind": "skeleton_vanguard", "n": 6})
    z.add("trigger", mid(choir), radius=700, id="choir", text="The choir. A red spire hums in the floor, and a robed figure kneels at its foot, singing.")
    # The great door to the Sepulcher of Mourning, barred from the far side
    ac = mid(apse)
    z.add("trigger", ac, radius=520, id="sepulcher_door", text="A great door of black iron at the end of the choir, standing open at last. The Sepulcher of Mourning lies beyond it, and something in it is weeping.")
    z.prop("crypt/decor_13", (apse[2], ac[1] - 1), dx=0.9, dy=0.95, scale=0.8)
    z.add("portal", (apse[2] - 1, ac[1]), target="sepulcher_of_mourning", requires="a1_descent_into_madness")  # barred until the third anchor is broken
    for dy in (-2, 2):
        z.prop("lantern_1", (apse[2] - 1, ac[1] + dy), dy=0.9, scale=0.5)

    _litter(z, [arrive, bones, cells, nave, choir])
    themes = [(bc, 8, "skeleton_vanguard"), (mid(cells), 7, "ghoul"), (mid(nave), 9, "skeleton_hunter"), (mid(choir), 9, "veil_cultist")]
    avoid = [(start, 8), (wp, 4), (morrow, 7), (anchor3, 4), ((4, 7), 3), (ac, 5)]
    z.packs(40, avoid, themes, min_gap=6, start=start, min_start=9)
    z.save("story")


def sepulcher_of_mourning():
    """The Sepulcher of Mourning (Act I, Chapter 5: Lord Malaphax, The Flesh-Torn): a sunken cathedral at the bottom of the Ossuary,
    the act's boss arena. A narthex in the west where the great door from the Lower Ossuary lets out, a long nave of colonnades and
    broken pews with the floor flooded under coagulated blood (mire: it slows you), two side chapels, and in the east the apse:
    an altar before a massive torn rift in the wall, where Lord Malaphax (formerly Duke Edward of Oakhaven) waits.
    Broken stained glass hangs in the walls and lies on the floor. Theme "crypt"."""
    z = Zone("sepulcher_of_mourning", "Sepulcher of Mourning", 58, 44, seed=7701, theme="crypt")
    z.fill()
    narthex, nave, apse = (3, 16, 12, 28), (14, 13, 33, 31), (36, 8, 54, 36)
    chapel_n, chapel_s = (17, 4, 29, 9), (17, 35, 29, 40)
    for h in (narthex, nave, apse, chapel_n, chapel_s):
        z.hall(*h)
    mid = _mid
    start, wp = (6, 22), (9, 20)
    z.hallway(mid(narthex), mid(nave), 3)
    z.hallway(mid(nave), mid(apse), 5)
    z.hallway((23, 13), (23, 7), 3, first="y")
    z.hallway((23, 31), (23, 38), 3, first="y")
    boss_at = (47, 22)
    altar = (52, 22)
    # The nave's colonnades: a row of pillars down each side, the central aisle open
    for x in range(nave[0] + 2, nave[2] - 1, 3):
        for y in (nave[1] + 2, nave[3] - 2):
            z.wall[y][x] = True
    for x in range(apse[0] + 3, apse[2] - 9, 4):
        for y in (apse[1] + 2, apse[3] - 2):
            z.wall[y][x] = True
    z.reachable_only(start)

    # The flooded floor: mire over the nave's middle and the apse's approach (coagulated blood: walkable, slow)
    for x in range(nave[0] + 1, nave[2] + 1):
        for y in range(nave[1] + 5, nave[3] - 4):
            edge = x < nave[0] + 3 or x > nave[2] - 2 or y < nave[1] + 7 or y > nave[3] - 6
            if not z.wall[y][x] and z.water[y][x] == "." and (not edge or z.rng.random() < 0.65):
                z.water[y][x] = ","
    for x in range(apse[0], apse[0] + 7):
        for y in range(apse[1] + 4, apse[3] - 3):
            if not z.wall[y][x] and z.water[y][x] == "." and z.rng.random() < 0.8:
                z.water[y][x] = ","
    for y in range(narthex[1] + 1, narthex[3]):
        for x in range(narthex[2] - 2, narthex[2] + 1):
            if z.rng.random() < 0.5 and not z.wall[y][x]:
                z.water[y][x] = ","

    z.add("start", start)
    z.add("portal", (4, 22), target="grand_ossuary_2")
    z.add("waypoint", wp)
    z.add("trigger", (7, 22), radius=520, id="sepulcher_gate", text="The Sepulcher of Mourning. A cathedral under the earth. The air is thick, and the floor is wet in a way that is not water.")
    z.prop("crypt/decor_13", (3, 20), dx=0.3, dy=0.95, scale=0.5)
    for dy in (-2, 2):
        z.prop("lantern_1", (6, 22 + dy), dy=0.9, scale=0.5)

    # Stained glass in the walls, broken, and its shards on the floor beneath
    gi = 0
    for h in (narthex, nave, apse):
        for x in range(h[0] + 2, h[2] - 1, 5):
            gi += 1
            z.prop("crypt/glass_%d" % (gi % 3 + 1), (x, h[1]), dx=0.5, dy=0.15, scale=0.55)
            for k in range(2):
                z.prop("crypt/glass_shard_%d" % z.rng.choice([1, 2, 3]), (x + z.rng.choice([-1, 0, 1]), h[1] + 1 + k), dx=z.rng.uniform(0.2, 0.8), dy=z.rng.uniform(0.3, 0.9), scale=0.7)
    for h in (nave, apse):
        for x in range(h[0] + 4, h[2] - 1, 5):
            z.prop("torch_1", (x, h[3]), dx=0.5, dy=0.3, scale=0.5)
    for key in [(23, 7), (23, 38)]:
        z.prop("lantern_1", key, dy=0.9, scale=0.5)

    # Broken pews along the nave
    for x in range(nave[0] + 3, nave[2] - 2, 4):
        for y in (nave[1] + 3, nave[3] - 3):
            z.prop("decor_20", (x, y), dy=0.9, scale=0.5, solid=True)
    z.prop("decor_22", (nave[2] - 1, nave[1] + 1), dy=0.9, scale=0.5, solid=True)

    # The apse: the altar, the torn veil rift behind it, a ring of the red crystal, blood
    z.add("trigger", mid(nave), radius=700, id="sepulcher_nave", text="The nave: pews smashed, the colonnades hung with black ichor. Far ahead, behind the altar, the wall is torn open and glowing.")
    z.add("trigger", boss_at, radius=760, id="sepulcher_apse", text="The altar. Behind it the wall is torn from floor to vault, and the tear weeps red light. Something heavy stands before it, in armour.")
    z.prop("crypt/veil_rift", (apse[2], altar[1]), dx=0.95, dy=0.95, scale=1.4)
    z.prop("decor_22", altar, dx=0.5, dy=0.9, scale=1.5, solid=True)
    for dy in (-3, 3):
        z.prop("lantern_1", (altar[0] - 1, altar[1] + dy), dy=0.9, scale=0.55)
    for i in range(10):
        ang = i * math.tau / 10
        rc = (round(boss_at[0] + math.cos(ang) * 6.0), round(boss_at[1] + math.sin(ang) * 4.8))
        if z.open_around(rc, 0):
            z.prop("crypt/rift_" + str(z.rng.choice([1, 2, 3])), rc, dx=0.5, dy=0.9, scale=0.7 + z.rng.random() * 0.3)
    for dx, dy in [(-3, 1), (3, -2), (0, 3), (-5, -3), (4, 4)]:
        z.prop("crypt/blood_" + str(z.rng.choice([1, 2, 3])), (boss_at[0] + dx, boss_at[1] + dy), scale=0.6)
    z.add("boss", boss_at, id="lord_malaphax", name="Lord Malaphax, the Flesh-Torn", kind="demon", skin="death_knight", hp=14.0, size=2.1)
    z.add("quest_object", (altar[0] - 2, altar[1]), id="rift_scar", sprite="crypt/rift_2", scale=1.2, prompt="Look into the torn rift",
          text="You look into the tear. It is a jagged, weeping scar in the air, and beyond it there is a great dark that is not looking at you, yet. The cold that comes through smells of dust and of a long road east.")
    # The side chapels: bones and urns, and a few of the cult
    for c in (mid(chapel_n), mid(chapel_s)):
        for dx in (-3, 0, 3):
            z.prop("decor_22" if dx else "decor_20", (c[0] + dx, c[1]), dy=0.9, scale=0.5, solid=True)
        z.prop("hollow/bone_" + str(z.rng.choice([1, 4, 5, 6])), (c[0] + 1, c[1] + 1), scale=0.6)
    for h in (chapel_n, chapel_s):
        for x in range(h[0] + 2, h[2], 4):
            z.prop("torch_1", (x, h[1]), dy=0.35, scale=0.5)
    _litter(z, [narthex, nave, apse, chapel_n, chapel_s])

    themes = [(mid(nave), 8, "skeleton_vanguard"), (mid(chapel_n), 5, "veil_cultist"), (mid(chapel_s), 5, "veil_cultist"), (mid(apse), 8, "bleed_fiend")]
    avoid = [(start, 8), (wp, 4), (boss_at, 9), ((4, 22), 3), (altar, 5)]
    z.packs(24, avoid, themes, min_gap=6, start=start, min_start=9)
    z.save("story")


def _mini_zone(zid, name, cols, rows, seed, theme, halls, start):
    z = Zone(zid, name, cols, rows, seed=seed, theme=theme)
    z.fill()
    for h in halls:
        z.hall(*h)
    return z


def mini_cellar():
    """The Rot-Damp Cellar (a mini-dungeon, see MiniDungeons): one low room of rotted barrels and puddles, blood maggots in swarms, and
    at the far end a chest on a hoard that is not what it seems (MiniDungeon). Theme "crypt"."""
    room = (3, 3, 19, 10)
    z = _mini_zone("mini_cellar", "Rot-Damp Cellar", 23, 14, 8801, "crypt", [room], (6, 6))
    start = (6, 6)
    z.reachable_only(start)
    z.add("start", start)
    z.add("portal", (4, 6), target="$origin")
    z.prop("decor_7", (4, 4), scale=0.4)
    for x in range(room[0] + 2, room[2], 4):
        z.prop("torch_1", (x, room[1]), dy=0.35, scale=0.5)
    for x, y in [(6, 4), (7, 4), (11, 4), (14, 9), (9, 9), (17, 4), (17, 9)]:
        z.prop("decor_2" if (x + y) % 3 else "decor_17", (x, y), dx=z.rng.uniform(0.3, 0.7), scale=0.5, solid=True)
    for x, y in [(8, 6), (12, 7), (15, 6), (10, 8), (13, 5)]:
        z.prop("crypt/blood_" + str(z.rng.choice([1, 2, 3])), (x, y), scale=0.4)
    for x, y in [(5, 8), (12, 4), (16, 8)]:
        z.prop("decor_21", (x, y), dy=0.9, scale=0.45, solid=True)
    z.add("marker", (17, 6), id="chest")
    for c in [(9, 5), (12, 8), (14, 6), (8, 8)]:
        z.add("pack", c, kind="blood_maggot", min=4, max=6)
    z.save("story")


def mini_bonepit():
    """The Forgotten Bone Pit (a mini-dungeon): caverns littered with skeletal debris; the pit in the middle has a way in at each end,
    and when you step into it iron portcullises slam over both (the "gate" markers), shutting you in with an elite Skeleton
    Champion (MiniDungeon). Theme "hollow"."""
    entry, ra, rb, pit = (3, 10, 9, 17), (14, 3, 20, 9), (14, 20, 20, 26), (26, 11, 36, 19)
    z = _mini_zone("mini_bonepit", "Forgotten Bone Pit", 40, 30, 8802, "hollow", [entry, ra, rb, pit], (5, 13))
    start = (5, 13)
    z.hallway((9, 13), (17, 6), 2)
    z.hallway((9, 14), (17, 23), 2)
    z.hallway((17, 6), (31, 6), 2)
    z.hallway((31, 6), (31, 11), 1, first="y")
    z.hallway((17, 23), (31, 23), 2)
    z.hallway((31, 23), (31, 19), 1, first="y")
    z.reachable_only(start)
    z.add("start", start)
    z.add("portal", (4, 13), target="$origin")
    z.add("marker", (31, 15), id="pit")
    z.add("marker", (31, 8), id="gate")
    z.add("marker", (31, 22), id="gate")
    for _ in range(26):  # skeletal debris
        c = (z.rng.randint(3, 38), z.rng.randint(3, 26))
        if z.open_around(c, 0):
            z.prop("hollow/bone_" + str(z.rng.randint(1, 10)), c, dx=z.rng.uniform(0.2, 0.8), dy=z.rng.uniform(0.3, 0.9), scale=z.rng.choice([0.5, 0.6, 0.8]))
    for dx, dy in [(-3, -2), (3, -2), (-3, 2), (3, 2), (0, -3), (0, 3)]:  # the pit's rim of bones and old ribs
        z.prop("hollow/bone_" + str(z.rng.choice([1, 4, 5, 6])), (31 + dx, 15 + dy), scale=0.9)
    for c in [(17, 6), (17, 23), (7, 13)]:
        z.prop("crypt/lantern_1", c, dy=0.9, scale=0.45)
    z.add("trigger", (31, 15), radius=700, id="bone_pit", text="A pit of bones. Something tells you not to step in.")
    for c in [(17, 5), (17, 24), (19, 7)]:
        z.add("pack", c, kind="skeleton", min=3, max=4)
    z.save("story")


def mini_sanctum():
    """The Secluded Hermit's Sanctum (a mini-dungeon): a quiet cave with a bed, lanterns, crystals and an abandoned crafting bench (the
    "bench" marker: one free reroll, HermitBench). No monsters. Theme "hollow"."""
    entry, mid_, den = (3, 9, 8, 14), (13, 3, 20, 10), (25, 9, 33, 18)
    z = _mini_zone("mini_sanctum", "Hermit's Sanctum", 37, 22, 8803, "hollow", [entry, mid_, den], (5, 11))
    start = (5, 11)
    z.hallway((8, 11), (16, 6), 2)
    z.hallway((16, 6), (29, 6), 2)
    z.hallway((29, 6), (29, 9), 2, first="y")
    z.reachable_only(start)
    z.add("start", start)
    z.add("portal", (4, 11), target="$origin")
    z.add("marker", (29, 13), id="bench")
    z.prop("decor_14", (27, 11), scale=0.5, solid=True)  # a bed of straw and furs
    z.prop("decor_15", (31, 16), scale=0.5)
    for c in [(26, 10), (32, 10), (26, 17), (32, 17), (16, 5), (6, 10)]:
        z.prop("crypt/lantern_1", c, dy=0.9, scale=0.42)
    for _ in range(16):
        c = (z.rng.randint(3, 34), z.rng.randint(3, 19))
        if z.open_around(c, 0):
            z.prop("hollow/crystal_" + str(z.rng.choice([1, 2, 5, 9])), c, dx=z.rng.uniform(0.2, 0.8), scale=0.45)
    z.add("trigger", (29, 13), radius=600, id="hermit_sanctum", text="A hermit's sanctum, quiet and long abandoned. A crafting bench stands against the wall, still sharp.")
    z.save("story")


def mini_fissure():
    """The Weeping Fissure (a mini-dungeon): a pocket where the realm wall is almost shredded. Black but for a pool of light round you,
    crowded with monsters, and in the middle a Tainted Chest tethered to three elite guardians (the "chest" and "guardian"
    markers: it opens when they are dead, MiniDungeon). Theme "hollow"."""
    entry, c1, c2, c3 = (3, 14, 8, 20), (14, 4, 22, 12), (14, 22, 22, 30), (27, 12, 37, 22)
    z = _mini_zone("mini_fissure", "Weeping Fissure", 41, 34, 8804, "hollow", [entry, c1, c2, c3], (5, 17))
    start = (5, 17)
    z.hallway((8, 17), (18, 8), 2)
    z.hallway((8, 18), (18, 26), 2)
    z.hallway((18, 8), (32, 8), 2)
    z.hallway((32, 8), (32, 12), 2, first="y")
    z.hallway((18, 26), (32, 26), 2)
    z.hallway((32, 26), (32, 22), 2, first="y")
    z.reachable_only(start)
    z.add("start", start)
    z.add("portal", (4, 17), target="$origin")
    z.add("marker", (32, 17), id="chest")
    for c in [(29, 14), (35, 14), (32, 20)]:
        z.add("marker", c, id="guardian")
    for _ in range(30):
        c = (z.rng.randint(3, 38), z.rng.randint(3, 30))
        if z.open_around(c, 0):
            z.prop("hollow/crystal_" + str(z.rng.randint(1, 10)), c, dx=z.rng.uniform(0.2, 0.8), dy=z.rng.uniform(0.4, 0.95), scale=z.rng.choice([0.5, 0.7]))
    for c in [(19, 8), (19, 26), (6, 17)]:
        z.prop("crypt/blood_" + str(z.rng.choice([1, 2, 3])), c, scale=0.5)
    z.add("trigger", (32, 17), radius=700, id="weeping_fissure", text="The Weeping Fissure. The dark is thick here, and the wall between the worlds is almost gone.")
    z.save("story")


if __name__ == "__main__":
    dune_wastes()
    oakhaven()
    weeping_hollow()
    sunken_fen()
    ashen_verge()
    grand_ossuary_1()
    grand_ossuary_2()
    sepulcher_of_mourning()
    mini_cellar()
    mini_bonepit()
    mini_sanctum()
    mini_fissure()
