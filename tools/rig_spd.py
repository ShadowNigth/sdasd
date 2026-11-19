"""Recover the Unity bind poses and first-person idle grips as Godot glTF rigs."""
import json
import re
import sys
from pathlib import Path

import numpy as np
import yaml

from convert_spd import Obj, ROOT, documents, index_assets, read_mesh, vector

MIRROR = np.diag([1, 1, -1, 1])


def rotation(q):
    x, y, z, w = q / np.linalg.norm(q)
    return np.array([[1 - 2*(y*y + z*z), 2*(x*y - z*w), 2*(x*z + y*w)],
                     [2*(x*y + z*w), 1 - 2*(x*x + z*z), 2*(y*z - x*w)],
                     [2*(x*z - y*w), 2*(y*z + x*w), 1 - 2*(x*x + y*y)]])


def load_rig(cache, assets, name, prefab):
    mesh_path = cache / 'Mesh' / (name + '.asset')
    scene = documents(cache / prefab)
    data = next(d for kind, d in scene.values() if kind == 'SkinnedMeshRenderer'
                and assets.get(d['m_Mesh'].get('guid')) == mesh_path)
    ids = [p['fileID'] for p in data['m_Bones']]
    labels = [scene[scene[i][1]['m_GameObject']['fileID']][1]['m_Name'] for i in ids]
    parents = []
    for key in ids:
        parent = scene[key][1]['m_Father']['fileID']
        while parent != '0' and parent not in ids:
            parent = scene[parent][1]['m_Father']['fileID']
        parents.append(ids.index(parent) if parent in ids else -1)
    m = next(iter(documents(mesh_path).values()))[1]
    bind = np.array([[[float(p[f'e{r}{c}']) for c in range(4)] for r in range(4)]
                     for p in m['m_BindPose']])
    skin = m['m_Skin']
    joints = np.array([[int(p[f'boneIndex[{j}]']) for j in range(4)] for p in skin])
    weights = np.array([[float(p[f'weight[{j}]']) for j in range(4)] for p in skin])
    weights /= weights.sum(axis=1, keepdims=True)
    assert len(bind) == len(ids)
    return read_mesh(mesh_path), data['m_Materials'], labels, parents, bind, joints, weights


def read_grip(path):
    # Keep just the first sample of each track. Unity curves preserve the full
    # transform path, including non-skin parents in the view-model hierarchy.
    text = re.split(r'^--- !u!\d+ &\d+\s*\n', path.read_text(), flags=re.M)[1]
    clip = yaml.load(text, Loader=yaml.CBaseLoader)['AnimationClip']
    transforms = {}
    for key in ('m_PositionCurves', 'm_RotationCurves', 'm_ScaleCurves'):
        for track in clip[key]:
            transforms.setdefault(track['path'], {})[key] = track['curve']['m_Curve'][0]['value']
    world = {'': np.eye(4)}
    for path, values in sorted(transforms.items(), key=lambda item: item[0].count('/')):
        if not path:
            continue
        m = np.eye(4)
        if 'm_RotationCurves' in values:
            m[:3, :3] = rotation(vector(values['m_RotationCurves'], 'xyzw'))
        if 'm_ScaleCurves' in values:
            m[:3, :3] *= vector(values['m_ScaleCurves'])
        if 'm_PositionCurves' in values:
            m[:3, 3] = vector(values['m_PositionCurves'])
        world[path] = world.get(path.rpartition('/')[0], np.eye(4)) @ m
    return {p.rsplit('/', 1)[-1]: m for p, m in world.items()}


def bake_arms(cache, assets, grip, name):
    mesh, materials, labels, parents, bind, joints, weights = load_rig(
        cache, assets, name, f'gameres/sdk/models/weapons/{name}/{name}.prefab')
    vertices, uv, parts = mesh
    rest = np.linalg.inv(bind)
    posed = {}
    def pose(i):
        if i in posed:
            return posed[i]
        parent = parents[i]
        posed[i] = grip.get(labels[i])
        if posed[i] is None:
            posed[i] = pose(parent) @ bind[parent] @ rest[i] if parent >= 0 else rest[i]
        return posed[i]
    matrices = np.stack([pose(i) for i in range(len(labels))]) @ bind
    points = np.einsum('nkij,nj->nki', matrices[joints], np.c_[vertices, np.ones(len(vertices))])
    points = np.einsum('nki,nk->ni', points, weights)[:, :3]
    obj = Obj(ROOT / 'models' / f'{name}_grip.obj', assets)
    obj.geometry(points, uv, [part[:, ::-1] for part in parts], np.eye(4), materials)
    obj.save()
    print(name, np.round(points.min(0), 3), np.round(points.max(0), 3), flush=True)


class Gltf:
    def __init__(self, path):
        self.path = path
        self.data = bytearray()
        self.doc = {'asset': {'version': '2.0'}, 'scene': 0, 'scenes': [], 'nodes': [], 'meshes': [],
                    'skins': [], 'accessors': [], 'bufferViews': [], 'materials': [], 'images': [], 'textures': []}

    def accessor(self, data, component, shape, bounds=False):
        self.data.extend(bytes((-len(self.data)) % 4))
        raw = data.tobytes()
        view = len(self.doc['bufferViews'])
        self.doc['bufferViews'].append({'buffer': 0, 'byteOffset': len(self.data), 'byteLength': len(raw)})
        self.data.extend(raw)
        index = len(self.doc['accessors'])
        accessor = {'bufferView': view, 'componentType': component, 'type': shape, 'count': len(data)}
        if bounds:
            accessor.update(min=data.min(axis=0).tolist(), max=data.max(axis=0).tolist())
        self.doc['accessors'].append(accessor)
        return index

    def save(self):
        binary = self.path.with_suffix('.bin')
        binary.write_bytes(self.data)
        self.doc['buffers'] = [{'byteLength': len(self.data), 'uri': binary.name}]
        self.path.write_text(json.dumps(self.doc, separators=(',', ':')) + '\n')


def export_character(cache, assets, name, prefab):
    mesh, materials, labels, parents, bind, joints, weights = load_rig(cache, assets, name, prefab)
    vertices, uv, parts = mesh
    normals = np.zeros_like(vertices)
    for triangles in parts:
        a, b, c = vertices[triangles].transpose(1, 0, 2)
        n = np.cross(b-a, c-a)
        for column in triangles.T:
            np.add.at(normals, column, n)
    normals /= np.maximum(np.linalg.norm(normals, axis=1, keepdims=True), 1e-9)
    gltf = Gltf(ROOT / 'models' / f'{name}_rig.gltf')
    pos = gltf.accessor((vertices * [1, 1, -1]).astype('<f4'), 5126, 'VEC3', True)
    norm = gltf.accessor((normals * [1, 1, -1]).astype('<f4'), 5126, 'VEC3')
    tex = gltf.accessor((uv * [1, -1] + [0, 1]).astype('<f4'), 5126, 'VEC2')
    joint = gltf.accessor(joints.astype('<u2'), 5123, 'VEC4')
    weight = gltf.accessor(weights.astype('<f4'), 5126, 'VEC4')
    inv = MIRROR @ bind @ MIRROR
    inverses = gltf.accessor(inv.transpose(0, 2, 1).astype('<f4'), 5126, 'MAT4')
    rest = np.linalg.inv(inv)
    roots = []
    for i, parent in enumerate(parents):
        local = inv[parent] @ rest[i] if parent >= 0 else rest[i]
        node = {'name': labels[i], 'matrix': local.T.flatten().tolist()}
        children = [j for j, link in enumerate(parents) if link == i]
        if children:
            node['children'] = children
        if parent < 0:
            roots.append(i)
        gltf.doc['nodes'].append(node)
    gltf.doc['nodes'].append({'name': name, 'mesh': 0, 'skin': 0})
    gltf.doc['scenes'] = [{'nodes': roots + [len(labels)]}]
    gltf.doc['skins'] = [{'inverseBindMatrices': inverses, 'joints': list(range(len(labels)))}]
    prim = []
    for i, triangles in enumerate(parts):
        idx = gltf.accessor(triangles[:, ::-1].astype('<u2').ravel(), 5123, 'SCALAR')
        mat = {'pbrMetallicRoughness': {'metallicFactor': 0, 'roughnessFactor': 0.89}}
        source = assets[materials[i]['guid']]
        m = re.search(r'_MainTex:\s*\n\s*m_Texture: .*guid: (\w+)', source.read_text())
        if m and m[1] in assets:
            texture = assets[m[1]]
            import shutil
            shutil.copyfile(texture, gltf.path.parent / texture.name)
            index = len(gltf.doc['images'])
            gltf.doc['images'].append({'uri': texture.name})
            gltf.doc['textures'].append({'source': index})
            mat['pbrMetallicRoughness']['baseColorTexture'] = {'index': index}
        gltf.doc['materials'].append(mat)
        prim.append({'indices': idx, 'material': i, 'attributes': {'POSITION': pos, 'NORMAL': norm,
                     'TEXCOORD_0': tex, 'JOINTS_0': joint, 'WEIGHTS_0': weight}})
    gltf.doc['meshes'] = [{'primitives': prim}]
    gltf.save()


def main(decompiled):
    cache = decompiled / 'GameCacheExport/ExportedProject/Assets'
    assets = index_assets(cache)
    grip = read_grip(cache / 'AnimationClip/idle.anim')
    for arms in ('ct_arms', 't_arms'):
        bake_arms(cache, assets, grip, arms)
    for name, prefab in [('ctm_idf', 'player_idf/Player_IDF'), ('tm_leet_variantA', 'player_leet_a/Player_LEET_A')]:
        export_character(cache, assets, name, f'gameres/sdk/models/players/{prefab}.prefab')


if __name__ == '__main__':
    main(Path(sys.argv[1]))
