import math

def get_transform(pos, rot_x_deg):
    rot_x = math.radians(rot_x_deg)
    
    Xx, Yx, Zx = 1.0, 0.0, 0.0
    Xy = 0.0
    Yy = math.cos(rot_x)
    Zy = -math.sin(rot_x)
    
    Xz = 0.0
    Yz = math.sin(rot_x)
    Zz = math.cos(rot_x)
    
    return f"Transform3D({Xx:g}, {Yx:g}, {Zx:g}, {Xy:g}, {Yy:g}, {Zy:g}, {Xz:g}, {Yz:g}, {Zz:g}, {pos[0]:g}, {pos[1]:g}, {pos[2]:g})"

def compute_track():
    sections = []
    
    # Section 1
    s1_len = 40
    s1_rot = 0
    s1_center = (0, 0, 0)
    sections.append({"name": "Section1_Floor", "size": (12, 0.5, s1_len), "pos": s1_center, "rot": s1_rot})
    
    # End of Section 1 (Z = -20)
    current_end = [0, 0, -s1_len/2.0]
    
    # Section 2
    s2_len = 10
    s2_rot = -45
    dir_y = math.sin(math.radians(-s2_rot)) # -sin(-45) = sin(45) = 0.707
    dir_z = -math.cos(math.radians(-s2_rot)) # -cos(45) = -0.707
    s2_center = (0, current_end[1] + dir_y * s2_len/2.0, current_end[2] + dir_z * s2_len/2.0)
    sections.append({"name": "Section2_Ramp", "size": (12, 0.5, s2_len), "pos": s2_center, "rot": s2_rot})
    current_end = [0, current_end[1] + dir_y * s2_len, current_end[2] + dir_z * s2_len]
    
    # Section 3
    s3_len = 40
    s3_rot = -90
    dir_y = 1
    dir_z = 0
    s3_center = (0, current_end[1] + dir_y * s3_len/2.0, current_end[2] + dir_z * s3_len/2.0)
    sections.append({"name": "Section3_Wall", "size": (12, 0.5, s3_len), "pos": s3_center, "rot": s3_rot})
    current_end = [0, current_end[1] + dir_y * s3_len, current_end[2] + dir_z * s3_len]
    
    # Section 4
    s4_len = 10
    s4_rot = -135
    dir_y = math.sin(math.radians(45)) # 0.707
    dir_z = math.cos(math.radians(45)) # 0.707
    s4_center = (0, current_end[1] + dir_y * s4_len/2.0, current_end[2] + dir_z * s4_len/2.0)
    sections.append({"name": "Section4_Ramp2", "size": (12, 0.5, s4_len), "pos": s4_center, "rot": s4_rot})
    current_end = [0, current_end[1] + dir_y * s4_len, current_end[2] + dir_z * s4_len]
    
    # Section 5
    s5_len = 40
    s5_rot = -180
    dir_y = 0
    dir_z = 1
    s5_center = (0, current_end[1] + dir_y * s5_len/2.0, current_end[2] + dir_z * s5_len/2.0)
    sections.append({"name": "Section5_Ceiling", "size": (12, 0.5, s5_len), "pos": s5_center, "rot": s5_rot})
    
    return sections

sections = compute_track()

tscn = """[gd_scene format=3 uid="uid://cx6523dm826a"]

[ext_resource type="Script" uid="uid://bgtt04kdo5wm0" path="res://scripts/vehicle/VehiclePhysics.gd" id="1_vehicle_physics"]
[ext_resource type="Script" uid="uid://cryeatod7dxq8" path="res://scripts/vehicle/VehicleController.gd" id="2_vehicle_controller"]
[ext_resource type="Script" uid="uid://bly3rs4qbutw5" path="res://scripts/tests/DebugOverlay.gd" id="3_debug_overlay"]
[ext_resource type="Script" uid="uid://g7b3784hlr71" path="res://scripts/camera/DynamicCamera.gd" id="4_dynamic_camera"]
[ext_resource type="Script" path="res://scripts/vehicle/GravitySystem.gd" id="5_gravity_system"]

[sub_resource type="ProceduralSkyMaterial" id="ProceduralSkyMaterial_sky"]

[sub_resource type="Sky" id="Sky_env"]
sky_material = SubResource("ProceduralSkyMaterial_sky")

[sub_resource type="Environment" id="Environment_world"]
background_mode = 2
sky = SubResource("Sky_env")

"""

for i, sec in enumerate(sections):
    tscn += f'[sub_resource type="BoxShape3D" id="BoxShape_sec{i+1}"]\nsize = Vector3({sec["size"][0]}, {sec["size"][1]}, {sec["size"][2]})\n\n'
    tscn += f'[sub_resource type="BoxMesh" id="BoxMesh_sec{i+1}"]\nsize = Vector3({sec["size"][0]}, {sec["size"][1]}, {sec["size"][2]})\n\n'

tscn += """[sub_resource type="CapsuleShape3D" id="CapsuleShape_vehicle"]
radius = 0.8
height = 1.6

[sub_resource type="BoxMesh" id="BoxMesh_vehicle"]
size = Vector3(1.6, 1, 2.4)

[node name="Test_GravityTransition" type="Node3D"]

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
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 1.5, -2)
script = ExtResource("1_vehicle_physics")

[node name="CollisionShape3D" type="CollisionShape3D" parent="Vehicle"]
shape = SubResource("CapsuleShape_vehicle")

[node name="MeshInstance3D" type="MeshInstance3D" parent="Vehicle"]
mesh = SubResource("BoxMesh_vehicle")

[node name="VehicleController" type="Node" parent="Vehicle"]
script = ExtResource("2_vehicle_controller")

[node name="GravitySystem" type="Node3D" parent="Vehicle"]
script = ExtResource("5_gravity_system")

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
offset_bottom = 140.0
theme_override_font_sizes/font_size = 18
text = "Debug overlay"
script = ExtResource("3_debug_overlay")
vehicle_path = NodePath("../../Vehicle")
"""

with open("/Users/abdul/Desktop/Personal/flowstate/flowstate/scenes/tests/Test_GravityTransition.tscn", "w") as f:
    f.write(tscn)

print("TSCN Generated successfully with connected track geometry!")
