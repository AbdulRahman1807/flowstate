import math

def get_transform(pos, rot_deg):
    rx, ry, rz = [math.radians(x) for x in rot_deg]
    
    # Standard Euler rotation matrices (YXZ order is common, but Godot uses YXZ by default)
    # Actually, simpler: let's build X, then Y, then Z.
    # X rotation
    cx, sx = math.cos(rx), math.sin(rx)
    Rx = [[1, 0, 0], [0, cx, -sx], [0, sx, cx]]
    # Y rotation
    cy, sy = math.cos(ry), math.sin(ry)
    Ry = [[cy, 0, sy], [0, 1, 0], [-sy, 0, cy]]
    # Z rotation
    cz, sz = math.cos(rz), math.sin(rz)
    Rz = [[cz, -sz, 0], [sz, cz, 0], [0, 0, 1]]
    
    # Godot uses Y-X-Z order for Euler angles (basis.set_euler)
    # R = Ry * Rx * Rz
    # Let's do matrix multiply manually
    def mul(A, B):
        return [[sum(a * b for a, b in zip(A_row, B_col)) for B_col in zip(*B)] for A_row in A]
    
    R = mul(Ry, Rx)
    R = mul(R, Rz)
    
    Xx, Yx, Zx = R[0][0], R[0][1], R[0][2]
    Xy, Yy, Zy = R[1][0], R[1][1], R[1][2]
    Xz, Yz, Zz = R[2][0], R[2][1], R[2][2]
    
    return f"Transform3D({Xx:g}, {Yx:g}, {Zx:g}, {Xy:g}, {Yy:g}, {Zy:g}, {Xz:g}, {Yz:g}, {Zz:g}, {pos[0]:g}, {pos[1]:g}, {pos[2]:g})"

sections = [
    {"name": "Section1_RunUp", "size": (12, 1, 50), "actual_size": (12, 1, 54), "pos": (0, 0, 0), "rot": (0, 0, 0)},
    {"name": "Section2_MainWall", "size": (12, 1, 40), "actual_size": (12, 1, 44), "pos": (0, 20, -25), "rot": (-90, 0, 0)},
    {"name": "Section3_Ceiling", "size": (12, 1, 20), "actual_size": (12, 1, 24), "pos": (0, 41, -35), "rot": (180, 0, 0)},
    {"name": "Section4_AngledWall", "size": (12, 1, 30), "actual_size": (12, 1, 34), "pos": (20, 15, -10), "rot": (-90, 30, 0)},
    {"name": "Section5_ShortWall", "size": (12, 1, 15), "actual_size": (12, 1, 19), "pos": (-20, 7, -10), "rot": (-90, 0, 0)}
]

tscn = """[gd_scene format=3 uid="uid://cx6523dm999b"]

[ext_resource type="Script" uid="uid://bgtt04kdo5wm0" path="res://scripts/vehicle/VehiclePhysics.gd" id="1_vehicle_physics"]
[ext_resource type="Script" uid="uid://cryeatod7dxq8" path="res://scripts/vehicle/VehicleController.gd" id="2_vehicle_controller"]
[ext_resource type="Script" uid="uid://bly3rs4qbutw5" path="res://scripts/tests/DebugOverlay.gd" id="3_debug_overlay"]
[ext_resource type="Script" uid="uid://g7b3784hlr71" path="res://scripts/camera/DynamicCamera.gd" id="4_dynamic_camera"]
[ext_resource type="Script" path="res://scripts/vehicle/GravitySystem.gd" id="5_gravity_system"]
[ext_resource type="Script" path="res://scripts/vehicle/WallRiding.gd" id="6_wall_riding"]
[ext_resource type="Script" path="res://scripts/systems/FlowSystem.gd" id="7_flow_system"]

[sub_resource type="ProceduralSkyMaterial" id="ProceduralSkyMaterial_sky"]

[sub_resource type="Sky" id="Sky_env"]
sky_material = SubResource("ProceduralSkyMaterial_sky")

[sub_resource type="Environment" id="Environment_world"]
background_mode = 2
sky = SubResource("Sky_env")

"""

for i, sec in enumerate(sections):
    tscn += f'[sub_resource type="BoxShape3D" id="BoxShape_sec{i+1}"]\nsize = Vector3({sec["actual_size"][0]}, {sec["actual_size"][1]}, {sec["actual_size"][2]})\n\n'
    tscn += f'[sub_resource type="BoxMesh" id="BoxMesh_sec{i+1}"]\nsize = Vector3({sec["actual_size"][0]}, {sec["actual_size"][1]}, {sec["actual_size"][2]})\n\n'

tscn += """[sub_resource type="CapsuleShape3D" id="CapsuleShape_vehicle"]
radius = 0.8
height = 1.6

[sub_resource type="BoxMesh" id="BoxMesh_vehicle"]
size = Vector3(1.6, 1, 2.4)

[node name="Test_WallRiding" type="Node3D"]

[node name="WorldEnvironment" type="WorldEnvironment" parent="."]
environment = SubResource("Environment_world")

[node name="DirectionalLight3D" type="DirectionalLight3D" parent="."]
transform = Transform3D(0.866025, -0.353553, 0.353553, 0, 0.707107, 0.707107, -0.5, -0.612372, 0.612372, 0, 12, 0)
shadow_enabled = true

"""

for i, sec in enumerate(sections):
    transform_str = get_transform(sec["pos"], sec["rot"])
    tscn += f'[node name="{sec["name"]}" type="StaticBody3D" parent="."]\ntransform = {transform_str}\n\n'
    tscn += f'[node name="CollisionShape3D" type="CollisionShape3D" parent="{sec["name"]}"]\nshape = SubResource("BoxShape_sec{i+1}")\n\n'
    tscn += f'[node name="MeshInstance3D" type="MeshInstance3D" parent="{sec["name"]}"]\nmesh = SubResource("BoxMesh_sec{i+1}")\n\n'

tscn += """[node name="Vehicle" type="CharacterBody3D" parent="."]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 2, 25)
script = ExtResource("1_vehicle_physics")

[node name="CollisionShape3D" type="CollisionShape3D" parent="Vehicle"]
shape = SubResource("CapsuleShape_vehicle")

[node name="MeshInstance3D" type="MeshInstance3D" parent="Vehicle"]
mesh = SubResource("BoxMesh_vehicle")

[node name="VehicleController" type="Node" parent="Vehicle"]
script = ExtResource("2_vehicle_controller")

[node name="GravitySystem" type="Node3D" parent="Vehicle"]
script = ExtResource("5_gravity_system")

[node name="WallRiding" type="Node" parent="Vehicle"]
script = ExtResource("6_wall_riding")

[node name="FlowSystem" type="Node" parent="Vehicle"]
script = ExtResource("7_flow_system")

[node name="Camera3D" type="Camera3D" parent="Vehicle"]
transform = Transform3D(1, 0, 0, 0, 0.939693, 0.34202, 0, -0.34202, 0.939693, 0, 3, 6)
current = true
script = ExtResource("4_dynamic_camera")
vehicle_path = NodePath("..")

[node name="DebugUI" type="CanvasLayer" parent="."]

[node name="DebugLabel" type="Label" parent="DebugUI"]
offset_left = 16.0
offset_top = 16.0
offset_right = 400.0
offset_bottom = 200.0
theme_override_font_sizes/font_size = 18
text = "Debug overlay"
script = ExtResource("3_debug_overlay")
vehicle_path = NodePath("../../Vehicle")
"""

with open("/Users/abdul/Desktop/Personal/flowstate/flowstate/scenes/tests/Test_WallRiding.tscn", "w") as f:
    f.write(tscn)

print("Test_WallRiding.tscn generated successfully!")
