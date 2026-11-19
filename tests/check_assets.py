"""Smoke-test converted assets without Unity or Godot."""
import json
import math
import re
import unittest
from pathlib import Path

ASSETS = Path(__file__).resolve().parents[1] / 'assets'


def mesh(path):
    vertices, faces = [], []
    for line in path.read_text().splitlines():
        if line.startswith('v '):
            vertices.append(tuple(map(float, line.split()[1:])))
        elif line.startswith('f '):
            faces.append(tuple(int(ref.split('/')[0]) - 1 for ref in line.split()[1:]))
    return vertices, faces


def floor_at(vertices, faces, point):
    x, y, z = point
    for face in faces:
        a, b, c = (vertices[i] for i in face)
        ux, uy, uz = (b[i] - a[i] for i in range(3))
        vx, vy, vz = (c[i] - a[i] for i in range(3))
        normal_y = uz * vx - ux * vz
        if normal_y <= 1e-8:
            continue
        dx, dz = x - a[0], z - a[2]
        s = (dz * vx - dx * vz) / normal_y
        t = (uz * dx - ux * dz) / normal_y
        floor_y = a[1] + s * uy + t * vy
        if s >= -1e-6 and t >= -1e-6 and s + t <= 1.000001 and -0.85 <= floor_y - y <= 0.05:
            return True
    return False


class ImportedAssets(unittest.TestCase):
    def test_meshes_and_materials(self):
        for obj in ASSETS.rglob('*.obj'):
            with self.subTest(obj=obj.name):
                vertices, faces = mesh(obj)
                self.assertTrue(vertices and faces)
                self.assertTrue(all(math.isfinite(value) for point in vertices for value in point))
                self.assertTrue(all(len(face) == 3 and all(0 <= i < len(vertices) for i in face) for face in faces))
                lines = obj.with_suffix('.mtl').read_text().splitlines()
                self.assertTrue(all((obj.parent / line[7:]).is_file() for line in lines if line.startswith('map_Kd ')))
                if any(line.startswith('map_Kd ') for line in lines):
                    uv = {line for line in obj.read_text().splitlines() if line.startswith('vt ')}
                    self.assertGreater(len(uv), 10, 'Textured mesh has collapsed UV coordinates')

    def test_original_spawns_have_a_floor(self):
        for name in ('2000', 'lego'):
            folder = ASSETS / 'maps'
            data = json.loads((folder / f'{name}.json').read_text())
            for suffix in ('', '_solid'):
                vertices, faces = mesh(folder / f'{name}{suffix}.obj')
                for team in ('ct', 't'):
                    self.assertGreaterEqual(len(data[team]), 5)
                    for spawn in data[team]:
                        with self.subTest(map=name + suffix, team=team, spawn=spawn):
                            self.assertTrue(floor_at(vertices, faces, spawn))

    def test_audio_headers(self):
        audio = list((ASSETS / 'audio').glob('*.ogg'))
        catalog = (ASSETS.parent / 'scripts/arsenal.gd').read_text()
        expected = set(re.findall(r'"sound": "([^"]+)"', catalog))
        self.assertTrue(expected.issubset({clip.stem for clip in audio}))
        models = set(re.findall(r'"mesh": "([^"]+)"', catalog))
        self.assertTrue(models.issubset({model.stem for model in (ASSETS / 'models').glob('*.obj')}))
        for clip in audio:
            self.assertEqual(clip.read_bytes()[:4], b'OggS')


if __name__ == '__main__':
    unittest.main()
