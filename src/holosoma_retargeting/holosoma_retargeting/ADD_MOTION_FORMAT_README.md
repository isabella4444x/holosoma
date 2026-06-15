## Instructions for Adding Custom Human Motion Data Format

This guide shows you how to add a new data format (e.g., "myformat") to the retargeting pipeline. We use SMPLX as an example, which is already implemented.

### Overview

1. **Prepare your data** (prepare .npz files which contain global joint positions and human height information)
2. **Add your joint names** (create a constant like `MYFORMAT_DEMO_JOINTS`)
3. **Register your format** in the unified registry (`DEMO_JOINTS_REGISTRY`)
4. **Add format-specific constants** (toe names, joint mappings, height)

### Step 1: Prepare Your Data Files

Prepare `.npz` files for each motion sequence:
- **`.npz` format**: Should contain `global_joint_positions` array (T X J X 3) and `height` scalar

**Example**: We provide `data_utils/prep_amass_smplx_for_rt.py` for converting AMASS SMPLX data:
```bash
# Install dependencies
conda create -n hsamass python=3.11 -y
conda activate hsamass
python -m pip install -U pip setuptools wheel
python -m pip install --index-url https://download.pytorch.org/whl/cpu torch

cd holosoma_retargeting/data_utils/
python -m pip install -U tqdm dotmap PyYAML omegaconf loguru tyro

# Run data processing
python prep_amass_smplx_for_rt.py \
    --amass-root-folder /path/to/amass \
    --output-folder /path/to/output \
    --model-root-folder /path/to/models
```

#### 2.1: Define Joint Names

Add a constant with your joint names. **Important**: The order of joint names must match the order of joints in the `J` dimension of your `global_joint_positions` array from Step 1.

For example, if your `global_joint_positions` array has shape `(T, J, 3)` where:
- `T` = number of timesteps
- `J` = number of joints
- `3` = x, y, z coordinates

Then `MYFORMAT_DEMO_JOINTS[0]` should be the name of the joint at `global_joint_positions[:, 0, :]`, `MYFORMAT_DEMO_JOINTS[1]` should be the name of the joint at `global_joint_positions[:, 1, :]`, and so on.

```python
MYFORMAT_DEMO_JOINTS = [
    "Joint1",  # Corresponds to global_joint_positions[:, 0, :]
    "Joint2",  # Corresponds to global_joint_positions[:, 1, :]
    # ... list all joints in order matching the J dimension
]
```

#### 2.2: Register Your Format

Add your format to the unified registry (this is the **main place** to register):

```python
DEMO_JOINTS_REGISTRY: dict[str, list[str]] = {
    "lafan": LAFAN_DEMO_JOINTS,
    "smplh": SMPLH_DEMO_JOINTS,
    "mocap": MOCAP_DEMO_JOINTS,
    "smplx": SMPLX_DEMO_JOINTS,
    "myformat": MYFORMAT_DEMO_JOINTS,  # ← Add your format here
}
```

#### 2.3: Add Format-Specific Constants

Add entries to these dictionaries.

**Required:**
- `TOE_NAMES_BY_FORMAT` - Must include toe joint names for foot-sticking constraint
- `JOINTS_MAPPINGS` - Must include mappings for each robot type you support

**Toe names** (used for foot sticking constraint):
```python
TOE_NAMES_BY_FORMAT = {
    # ... existing formats ...
    "myformat": ["LeftToe", "RightToe"],  # ← Add your toe joint names
}
```

**Joint mappings** (human joint → robot joint):
```python
JOINTS_MAPPINGS = {
    # ... existing mappings ...
    ("myformat", "g1"): {  # ← Add for each robot type you support
        "HumanJoint1": "robot_joint_1",
        "HumanJoint2": "robot_joint_2",
        # ... map all relevant joints
    },
    ("myformat", "t1"): {  # ← If supporting t1 robot
        # ... mappings for t1
    },
}
```

### Step 3: Add Data Loading Logic (if needed)

**Important**: If you processed your data to the `.npz` format in Step 1 (with `global_joint_positions` and `height` keys), you can **skip this step entirely**. The code automatically handles `.npz` files with this structure via a fallback mechanism.

If your format needs special loading logic (different file extension, custom preprocessing, etc.), edit `examples/robot_retarget.py` in the `load_motion_data()` function. Add your format before the fallback `else` clause:

```python
def load_motion_data(...):
    # ... existing code ...
    elif data_format == "smplx":
        npz_file = data_path / f"{task_name}.npz"
        human_data = np.load(str(npz_file))
        human_joints = human_data["global_joint_positions"]
        human_height = human_data["height"]
        smpl_scale = constants.ROBOT_HEIGHT / human_height
    elif data_format == "myformat":
        # Add your custom loading logic here
        npy_path = data_path / f"{task_name}.npy"
        human_joints = np.load(str(npy_path))
        # ... any preprocessing ...
        smpl_scale = constants.ROBOT_HEIGHT / default_human_height
    else:
        # Fallback: handles .npz files with global_joint_positions and height
        # ... (automatic handling for standard .npz format)
```


### Summary: What You Need to Edit

**In `config_types/data_type.py`** (main configuration file):
1. ✅ **Required**: Create `MYFORMAT_DEMO_JOINTS` constant
2. ✅ **Required**: Add to `DEMO_JOINTS_REGISTRY`
3. ✅ **Required**: Add to `TOE_NAMES_BY_FORMAT`
4. ✅ **Required**: Add to `JOINTS_MAPPINGS`

**In `examples/robot_retarget.py`** (only if needed):
7. ⚠️ **Optional**: Add loading logic in `load_motion_data()` (only if format needs special handling beyond standard `.npz` format)


### Ready to Run

Once configured, you can use your custom format:

```bash
python examples/robot_retarget.py \
  --data_path /path/to/your/data \
  --task-type robot_only \
  --task-name your_sequence_name \
  --data_format myformat \
  --retargeter.debug \
  --retargeter.visualize
```
