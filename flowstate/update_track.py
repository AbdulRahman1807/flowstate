import re

with open('scripts/tests/TrackBuilder.gd', 'r') as f:
    content = f.read()

new_content = """extends Node3D

func _ready() -> void:
    _build_track()

func _build_track() -> void:
    # Infinite floor — sits 20 units below track start, catches all falls
    # Adding dark blue color
    _add_box(Vector3(2000, 1, 2000), Vector3(0, -21, -400), Vector3.ZERO, Color(0.1, 0.2, 0.3))

    # S1: Launch straight — 120 units long
    _add_box(Vector3(28, 1, 120), Vector3(0, 0, -60), Vector3.ZERO)

    # S2: S-curve
    _add_box(Vector3(28, 1, 40), Vector3(-12, 0, -135), Vector3.ZERO)
    _add_box(Vector3(28, 1, 20), Vector3(0, 0, -165), Vector3.ZERO)
    _add_box(Vector3(28, 1, 40), Vector3(12, 0, -190), Vector3.ZERO)

    # S3: Ramp
    _add_box(Vector3(28, 3, 12), Vector3(12, 1.5, -218), Vector3.ZERO)
    _add_box(Vector3(28, 1, 20), Vector3(12, 0, -248), Vector3.ZERO)

    # S4: Speed straight
    _add_box(Vector3(28, 1, 80), Vector3(12, 0, -298), Vector3.ZERO)

    # S5: Platform
    _add_box(Vector3(20, 1, 14), Vector3(12, 0, -344), Vector3.ZERO)
    _add_box(Vector3(20, 1, 14), Vector3(12, 0, -372), Vector3.ZERO)
    _add_box(Vector3(20, 1, 14), Vector3(12, 0, -402), Vector3.ZERO)
    _add_box(Vector3(20, 1, 14), Vector3(12, 0, -432), Vector3.ZERO)
    _add_box(Vector3(28, 1, 20), Vector3(12, 0, -462), Vector3.ZERO)

    # S6: Wall
    _add_box(Vector3(28, 1, 20), Vector3(12, 0, -486), Vector3.ZERO)
    _add_box(Vector3(28, 35, 1), Vector3(12, 17, -497), Vector3.ZERO)
    _add_box(Vector3(28, 1, 20), Vector3(12, 35, -507), Vector3.ZERO)

    # S7: Recovery
    _add_box(Vector3(28, 1, 60), Vector3(12, 35, -537), Vector3.ZERO)

    # S8: Lead-in
    _add_box(Vector3(28, 1, 10), Vector3(12, 35, -572), Vector3.ZERO)
    _add_box(Vector3(28, 1, 10), Vector3(12, 35, -592), Vector3.ZERO)
    _add_box(Vector3(28, 1, 20), Vector3(12, 35, -616), Vector3.ZERO)

    # S9: Canyon
    _add_box(Vector3(28, 1, 60), Vector3(12, 35, -656), Vector3.ZERO)
    _add_box(Vector3(1, 20, 60), Vector3(-2, 45, -656), Vector3.ZERO)
    _add_box(Vector3(1, 20, 60), Vector3(26, 45, -656), Vector3.ZERO)

    # S10
    _add_box(Vector3(28, 1, 20), Vector3(12, 35, -696), Vector3.ZERO)
    _add_box(Vector3(28, 40, 1), Vector3(12, 55, -707), Vector3.ZERO)
    _add_box(Vector3(28, 1, 40), Vector3(12, 76, -727), Vector3.ZERO)

    # S11
    _add_box(Vector3(40, 1, 20), Vector3(12, 35, -755), Vector3.ZERO)
    _add_box(Vector3(24, 1, 30), Vector3(-4, 35, -780), Vector3.ZERO)
    _add_box(Vector3(24, 1, 30), Vector3(20, 35, -815), Vector3.ZERO)
    _add_box(Vector3(24, 1, 30), Vector3(-4, 35, -850), Vector3.ZERO)

    # S12
    _add_box(Vector3(28, 1, 20), Vector3(-4, 35, -875), Vector3.ZERO)
    _add_box(Vector3(28, 4, 8), Vector3(-4, 37, -889), Vector3.ZERO)
    _add_box(Vector3(28, 30, 1), Vector3(-4, 50, -907), Vector3.ZERO)
    _add_box(Vector3(28, 1, 30), Vector3(-4, 65, -922), Vector3.ZERO)

    # S13
    _add_box(Vector3(40, 1, 20), Vector3(-4, 35, -958), Vector3.ZERO)
    _add_box(Vector3(28, 1, 80), Vector3(-4, 35, -1008), Vector3.ZERO)

    # S14
    _add_box(Vector3(28, 1, 40), Vector3(-4, 15, -1068), Vector3.ZERO)
    _add_box(Vector3(1, 22, 40), Vector3(-18, 26, -1068), Vector3.ZERO)
    _add_box(Vector3(1, 22, 40), Vector3(10, 26, -1068), Vector3.ZERO)
    _add_box(Vector3(28, 1, 20), Vector3(-4, 35, -1098), Vector3.ZERO)

    # S15
    _add_box(Vector3(28, 1, 20), Vector3(-4, 35, -1118), Vector3.ZERO)
    var loop_center := Vector3(-4, 55, -1140)
    var loop_radius := 20.0
    var num_segments := 12
    for i in range(num_segments):
        var angle_deg := i * 30.0
        var angle_rad := deg_to_rad(angle_deg)
        var offset_y := -sin(angle_rad) * loop_radius
        var offset_z := -cos(angle_rad) * loop_radius
        var seg_pos := loop_center + Vector3(0, offset_y, offset_z)
        var seg_rot := Vector3(angle_deg, 0, 0)
        _add_box(Vector3(28, 1, 12), seg_pos, seg_rot)
    _add_box(Vector3(28, 1, 20), Vector3(-4, 35, -1162), Vector3.ZERO)

    # S16
    var cork_start_z := -1192.0
    var cork_start_y := 35.0
    for ring in range(8):
        var ring_z := cork_start_z - (ring * 10.0)
        var ring_rot := ring * 45.0
        var ring_center := Vector3(-4, cork_start_y, ring_z - 5)
        var floor_offset := Vector3(0, -14, 0).rotated(Vector3(0, 0, 1), deg_to_rad(ring_rot))
        _add_box(Vector3(28, 1, 10), ring_center + floor_offset, Vector3(0, 0, ring_rot))
        var ceil_offset := Vector3(0, 14, 0).rotated(Vector3(0, 0, 1), deg_to_rad(ring_rot))
        _add_box(Vector3(28, 1, 10), ring_center + ceil_offset, Vector3(0, 0, ring_rot))
        var left_offset := Vector3(-14, 0, 0).rotated(Vector3(0, 0, 1), deg_to_rad(ring_rot))
        _add_box(Vector3(1, 28, 10), ring_center + left_offset, Vector3(0, 0, ring_rot))
        var right_offset := Vector3(14, 0, 0).rotated(Vector3(0, 0, 1), deg_to_rad(ring_rot))
        _add_box(Vector3(1, 28, 10), ring_center + right_offset, Vector3(0, 0, ring_rot))
    _add_box(Vector3(28, 1, 20), Vector3(-4, 35, -1282), Vector3.ZERO)

    # S17
    _add_box(Vector3(28, 1, 40), Vector3(-4, 35, -1312), Vector3.ZERO)
    _add_box(Vector3(28, 8, 10), Vector3(-4, 39, -1337), Vector3.ZERO)
    _add_box(Vector3(60, 1, 40), Vector3(-4, 35, -1368), Vector3.ZERO)
    _add_box(Vector3(1, 8, 1), Vector3(-32, 39, -1348), Vector3.ZERO)
    _add_box(Vector3(1, 8, 1), Vector3(24, 39, -1348), Vector3.ZERO)
    _add_box(Vector3(60, 1, 1), Vector3(-4, 47, -1348), Vector3.ZERO)

func _add_box(size: Vector3, position: Vector3, rotation_degrees: Vector3, color: Color = Color.TRANSPARENT) -> StaticBody3D:
    var body := StaticBody3D.new()
    body.position = position
    body.rotation_degrees = rotation_degrees
    
    var shape := CollisionShape3D.new()
    var box := BoxShape3D.new()
    box.size = size
    shape.shape = box
    body.add_child(shape)
    
    var mesh_instance := MeshInstance3D.new()
    var box_mesh := BoxMesh.new()
    box_mesh.size = size
    mesh_instance.mesh = box_mesh
    
    if color != Color.TRANSPARENT:
        var mat := StandardMaterial3D.new()
        mat.albedo_color = color
        mesh_instance.material_override = mat
        
    body.add_child(mesh_instance)
    
    add_child(body)
    return body
"""

with open('scripts/tests/TrackBuilder.gd', 'w') as f:
    f.write(new_content)
