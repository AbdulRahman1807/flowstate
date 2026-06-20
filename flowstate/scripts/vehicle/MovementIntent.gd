class_name MovementIntent

var steer: float = 0.0       # -1.0 (left) to 1.0 (right)
var accelerate: float = 0.0  # 0.0 to 1.0
var brake: float = 0.0       # 0.0 to 1.0
var jump: bool = false
var boost: bool = false
var wall_attach: bool = false
var drift: bool = false  # Explicit/programmatic drift override; players trigger drift via brake+steer (brake-to-drift)
