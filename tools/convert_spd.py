"""Convert recovered Unity meshes, materials, collision and spawns to local Godot assets.
Usage: python tools/convert_spd.py /path/to/spd/decompiled
Dependencies: numpy, PyYAML. This is an authoring tool, not a runtime dependency.
"""
import json
import re
import shutil
import sys
from functools import lru_cache
from pathlib import Path

import numpy as np
import yaml

ROOT = Path(__file__).resolve().parents[1] / 'assets'
AXES = 'xyz'


def documents(path):
    parts = re.split(r'^--- !u!\d+ &(-?\d+)\s*\n', path.read_text(), flags=re.M)
    return {key: next(iter(yaml.load(text, Loader=yaml.BaseLoader).items()))
            for key, text in zip(parts[1::2], parts[2::2])}


def vector(data, axes=AXES):
    return np.array([float(data[a]) for a in axes])


def index_assets(folder):
    result = {}
    for meta in sorted(folder.rglob('*.meta')):
        guid = re.search(r'^guid: (\w+)', meta.read_text(), re.M)
        if guid:
            result[guid[1]] = meta.with_suffix('')
    return result


@lru_cache(None)
def read_mesh(path):
    mesh = next(iter(documents(path).values()))[1]
    vd = mesh['m_VertexData']
    channels = vd['m_Channels']
    stride = sum(int(c['dimension']) * (4, 2, 1, 1, 4)[int(c['format'])]
                 for c in channels if c['stream'] == '0')
    raw = bytes.fromhex(vd['_typelessdata'])
    count = int(vd['m_VertexCount'])
    def channel(i, dimension):
        c = channels[i]
        if int(c['dimension']) < dimension or c['format'] != '0' or c['stream'] != '0':
            return np.zeros((count, dimension))
        return np.ndarray((count, dimension), '<f4', raw, int(c['offset']), (stride, 4)).copy()
    uv_channel = 3 if int(mesh['serializedVersion']) <= 8 else 4
    dtype = '<u2' if mesh['m_IndexFormat'] == '0' else '<u4'
    indices = np.frombuffer(bytes.fromhex(mesh['m_IndexBuffer']), dtype)
    parts = []
    for sub in mesh['m_SubMeshes']:
        assert sub['topology'] == '0', path
        start = int(sub['firstByte']) // indices.itemsize
        parts.append(indices[start:start + int(sub['indexCount'])].reshape(-1, 3).astype(int)
                     + int(sub['baseVertex']))
    return channel(0, 3), channel(uv_channel, 2), parts


class Obj:
    def __init__(self, path, assets):
        self.path = path
        self.assets = assets
        self.lines = []
        self.materials = {}
        self.offset = 1

    def add(self, path, matrix, materials=(), batch=None):
        vertices, uv, parts = read_mesh(path)
        self.geometry(vertices, uv, [part[:, ::-1] for part in parts], matrix, materials, batch)

    def geometry(self, vertices, uv, parts, matrix, materials=(), batch=None):
        if batch and int(batch['subMeshCount']):
            start = int(batch['firstSubMesh'])
            parts = parts[start:start + int(batch['subMeshCount'])]
        used = np.unique(np.concatenate(parts))
        parts = [np.searchsorted(used, faces) for faces in parts]
        vertices, uv = vertices[used], uv[used]
        points = vertices @ matrix[:3, :3].T + matrix[:3, 3]
        points[:, 2] *= -1
        self.lines.extend('v %.6f %.6f %.6f' % tuple(p) for p in points)
        self.lines.extend('vt %.6f %.6f' % tuple(p) for p in uv)
        for i, faces in enumerate(parts):
            guid = materials[min(i, len(materials)-1)].get('guid') if materials else 'plain'
            if guid not in self.materials:
                texture = None
                mat = self.assets.get(guid)
                if mat:
                    text = mat.read_text()
                    match = re.search(r'_MainTex:\s*\n\s*m_Texture: .*guid: (\w+)', text)
                    if match:
                        texture = self.assets.get(match[1])
                self.materials[guid] = texture
            self.lines.append(f'usemtl m_{guid}')
            self.lines.append('s 1' if self.path.parent.name == 'models' else 's off')
            if np.linalg.det(matrix[:3, :3]) < 0:
                faces = faces[:, ::-1]
            for face in faces + self.offset:
                self.lines.append('f ' + ' '.join(f'{j}/{j}' for j in face))
        self.offset += len(points)

    def save(self):
        mtl = self.path.with_suffix('.mtl')
        self.path.write_text(f'mtllib {mtl.name}\n' + '\n'.join(self.lines) + '\n')
        lines = []
        for guid, texture in self.materials.items():
            lines.extend([f'newmtl m_{guid}', 'Kd 0.75 0.75 0.75'])
            if texture and texture.suffix.lower() == '.png':
                name = re.sub(r'[^\w.-]', '_', texture.name)
                shutil.copyfile(texture, self.path.parent / name)
                lines.append('map_Kd ' + name)
        mtl.write_text('\n'.join(lines) + '\n')


def add_box(obj, matrix, collider, materials=()):
    corners = np.array([[-1, -1, -1], [1, -1, -1], [1, 1, -1], [-1, 1, -1],
                        [-1, -1, 1], [1, -1, 1], [1, 1, 1], [-1, 1, 1]])
    quads = np.array([[0, 1, 2, 3], [5, 4, 7, 6], [4, 0, 3, 7],
                      [1, 5, 6, 2], [3, 2, 6, 7], [4, 5, 1, 0]])
    vertices = (corners[quads.flatten()] * vector(collider['m_Size']) * 0.5
                + vector(collider['m_Center']))
    uv = np.tile([[0, 0], [1, 0], [1, 1], [0, 1]], (6, 1))
    faces = np.array([[0, 1, 2], [0, 2, 3]] * 6) + np.repeat(np.arange(6) * 4, 2)[:, None]
    obj.geometry(vertices, uv, [faces], matrix, materials)


def convert_level(base, assets, source_name, name):
    scene = documents(base / 'GameRes/Levels' / (source_name + '.unity'))
    by_object = {}
    for key, (kind, data) in scene.items():
        if 'm_GameObject' in data:
            by_object.setdefault(data['m_GameObject']['fileID'], {}).setdefault(kind, []).append((key, data))

    @lru_cache(None)
    def transform(key):
        if key == '0':
            return np.eye(4)
        t = scene[key][1]
        x, y, z, w = vector(t['m_LocalRotation'], 'xyzw')
        rot = np.array([[1-2*(y*y+z*z), 2*(x*y-z*w), 2*(x*z+y*w)],
                        [2*(x*y+z*w), 1-2*(x*x+z*z), 2*(y*z-x*w)],
                        [2*(x*z-y*w), 2*(y*z+x*w), 1-2*(x*x+y*y)]])
        matrix = np.eye(4)
        matrix[:3, :3] = rot @ np.diag(vector(t['m_LocalScale']))
        matrix[:3, 3] = vector(t['m_LocalPosition'])
        return transform(t['m_Father']['fileID']) @ matrix

    visible = Obj(ROOT / 'maps' / (name + '.obj'), assets)
    physics = Obj(ROOT / 'maps' / (name + '_solid.obj'), assets)
    spawns = {'ct': [], 't': [], 'ladders': []}
    for key, (kind, data) in scene.items():
        if kind != 'GameObject' or data['m_IsActive'] != '1' or key not in by_object:
            continue
        components = by_object[key]
        if 'Transform' not in components:
            continue
        matrix = transform(components['Transform'][0][0])
        label = data['m_Name']
        if label in ('SpawnCT', 'SpawnT'):
            spawns[label[5:].lower()].append((matrix[:3, 3] * [1, 1, -1]).round(4).tolist())
        if 'MeshFilter' in components and 'MeshRenderer' in components:
            renderer = components['MeshRenderer'][0][1]
            mesh = assets.get(components['MeshFilter'][0][1]['m_Mesh'].get('guid'))
            if mesh and renderer['m_Enabled'] == '1':
                batch = renderer.get('m_StaticBatchInfo')
                if batch and int(batch['subMeshCount']):
                    # Static batch vertices already use the batch root's coordinate space.
                    root = renderer['m_StaticBatchRoot']['fileID']
                    matrix_for_render = transform(root) if root in scene else np.eye(4)
                else:
                    matrix_for_render = matrix
                visible.add(mesh, matrix_for_render, renderer['m_Materials'], batch)
                if label.startswith('Ladder') and batch and int(batch['subMeshCount']):
                    vertices, _, parts = read_mesh(mesh)
                    ids = parts[int(batch['firstSubMesh'])].ravel()
                    transformed = vertices[ids] @ matrix_for_render[:3, :3].T + matrix_for_render[:3, 3]
                    transformed[:, 2] *= -1
                    spawns['ladders'].append([transformed.min(axis=0).tolist(), transformed.max(axis=0).tolist()])
        for _, collider in components.get('BoxCollider', []):
            if collider['m_IsTrigger'] == '0' and collider['m_Enabled'] == '1':
                add_box(physics, matrix, collider)
                if label.startswith('Cube') and 'MeshRenderer' in components:
                    add_box(visible, matrix, collider, components['MeshRenderer'][0][1]['m_Materials'])
        for _, collider in components.get('MeshCollider', []):
            mesh = assets.get(collider['m_Mesh'].get('guid'))
            if mesh and collider['m_IsTrigger'] == '0' and collider['m_Enabled'] == '1':
                physics.add(mesh, matrix)
    for obj in (visible, physics):
        assert obj.offset > 1
        obj.save()
    assert spawns['ct'] and spawns['t']
    (ROOT / 'maps' / (name + '.json')).write_text(json.dumps(spawns, indent=2) + '\n')
    print(name, visible.offset - 1, physics.offset - 1, {k: len(v) for k, v in spawns.items()})


def main(decompiled):
    base, cache = (decompiled / export / 'ExportedProject/Assets'
                   for export in ('AssetRipperExport', 'GameCacheExport'))
    for directory in ('maps', 'audio', 'models'):
        (ROOT / directory).mkdir(parents=True, exist_ok=True)
    assets = index_assets(base)
    for source, name in [('$2000$', '2000'), ('awp_lego_2', 'lego')]:
        convert_level(base, assets, source, name)
    catalog = (ROOT.parent / 'scripts/arsenal.gd').read_text()
    sounds = set(re.findall(r'"sound": "([^"]+)"', catalog))
    sounds.update(('ak47_clipin', 'grenade_throw', 'explode3', 'flashbang_explode1', 'smoke_emit'))
    for name in sorted(sounds):
        shutil.copyfile(cache / 'AudioClip' / (name + '.ogg'), ROOT / 'audio' / (name + '.ogg'))
    textures = {'w_rif_ak47': 'ak47', 'w_snip_awp': 'awp', 'w_pist_deagle': 'pist_deagle'}
    names = set(re.findall(r'"mesh": "([^"]+)"', catalog))
    names.update(('ctm_idf', 'tm_leet_variantA', 'w_eq_flashbang',
                  'w_eq_fraggrenade_combine', 'w_eq_smokegrenade_combine', 'w_knife_default_t', 'w_ied_w_eq_c4'))
    for name in sorted(names):
        obj = Obj(ROOT / 'models' / (name + '.obj'), {})
        obj.add(cache / 'Mesh' / (name + '.asset'), np.eye(4))
        key = name.removeprefix('w_').removesuffix('_combine')
        guesses = [textures.get(name, key), key.partition('_')[2]]
        for texture in guesses:
            path = cache / 'Texture2D' / (texture + '.png')
            if path.is_file():
                obj.materials['plain'] = path
                break
        obj.save()


if __name__ == '__main__':
    main(Path(sys.argv[1]))
