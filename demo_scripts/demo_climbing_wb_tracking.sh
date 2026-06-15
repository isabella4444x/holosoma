#!/usr/bin/env bash

# Script for running climbing retargeting, data conversion, and whole-body tracking training.
# Requires Ubuntu/Linux OS (IsaacSim is not supported on Mac)

set -e

# figure out where this file is located even if it is being run from another location
# or as a symlink
SOURCE="${BASH_SOURCE[0]:-${(%):-%x}}"
while [ -h "$SOURCE" ]; do
  DIR="$( cd -P "$( dirname "$SOURCE" )" >/dev/null && pwd )"
  SOURCE="$(readlink "$SOURCE")"
  [[ $SOURCE != /* ]] && SOURCE="$DIR/$SOURCE"
done
SCRIPT_DIR="$( cd -P "$( dirname "$SOURCE" )" >/dev/null && pwd )"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

TASK_NAME="${TASK_NAME:-mocap_climb_seq_0}"
OBJECT_NAME="${OBJECT_NAME:-multi_boxes}"
TRAINING_NUM_ENVS="${TRAINING_NUM_ENVS:-4096}"
TRAINING_HEADLESS="${TRAINING_HEADLESS:-True}"
ISAAC_ENV_SPACING="${ISAAC_ENV_SPACING:-2.5}"
TERRAIN_SCALE_FACTOR="${TERRAIN_SCALE_FACTOR:-0.7415730337078652}"
INIT_AT_RANDOM_EP_LEN="${INIT_AT_RANDOM_EP_LEN:-False}"
VIEWER_ENABLE_TRACKING="${VIEWER_ENABLE_TRACKING:-True}"
VIEWER_CAMERA_TYPE="${VIEWER_CAMERA_TYPE:-fixed}"
VIEWER_CAMERA_POS="${VIEWER_CAMERA_POS:-2.5,-2.5,1.6}"
VIEWER_CAMERA_TARGET="${VIEWER_CAMERA_TARGET:-0.0,0.0,0.8}"
SKIP_EXISTING="${SKIP_EXISTING:-True}"

if [[ "$VIEWER_CAMERA_TYPE" != "fixed" ]]; then
    echo "Error: VIEWER_CAMERA_TYPE=$VIEWER_CAMERA_TYPE is not supported by this demo script. Use 'fixed'."
    exit 1
fi

if [[ "$(awk -F',' '{print NF}' <<< "$VIEWER_CAMERA_POS")" -ne 3 || "$(awk -F',' '{print NF}' <<< "$VIEWER_CAMERA_TARGET")" -ne 3 ]]; then
    echo "Error: VIEWER_CAMERA_POS and VIEWER_CAMERA_TARGET must each contain 3 comma-separated numbers."
    exit 1
fi

VIEWER_CAMERA_POS_ARG="[$VIEWER_CAMERA_POS]"
VIEWER_CAMERA_TARGET_ARG="[$VIEWER_CAMERA_TARGET]"

# Detect operating system and check if it's supported
OS="$(uname -s)"
case "${OS}" in
    Linux*)
        MACHINE=Linux
        echo "Detected Linux OS - proceeding..."
        ;;
    Darwin*)
        echo "Error: Mac OS is not supported. This script requires Ubuntu/Linux for IsaacSim."
        exit 1
        ;;
    CYGWIN*|MINGW*)
        echo "Error: Windows is not supported. This script requires Ubuntu/Linux for IsaacSim."
        exit 1
        ;;
    *)
        echo "Error: Unsupported operating system: ${OS}. This script requires Ubuntu/Linux for IsaacSim."
        exit 1
        ;;
esac

echo "Sourcing retargeting setup..."
source "$PROJECT_ROOT/scripts/source_retargeting_setup.sh"

# Ensure holosoma_retargeting is installed with correct dependencies.
pip install -e "$PROJECT_ROOT/src/holosoma_retargeting" --quiet

RETARGET_DIR="$PROJECT_ROOT/src/holosoma_retargeting/holosoma_retargeting"
cd "$RETARGET_DIR"

ASSET_CLIMB_DIR="${ASSET_CLIMB_DIR:-$PROJECT_ROOT/assets/climb/${TASK_NAME}}"
DEMO_CLIMB_DIR="$RETARGET_DIR/demo_data/climb/${TASK_NAME}"

RETARGETED_FILE="./demo_results/g1/climbing/mocap_climb/${TASK_NAME}_original.npz"
CONVERTED_FILE="$RETARGET_DIR/converted_res/climbing/${TASK_NAME}_mj.npz"
TERRAIN_OBJ_FILE="$ASSET_CLIMB_DIR/multi_boxes.obj"
SCALED_SCENE_XML_FILE="$DEMO_CLIMB_DIR/g1_29dof_spherehand_w_multi_boxes_scaled_0.74_0.74_0.74.xml"
DEFAULT_SCENE_XML_FILE="$DEMO_CLIMB_DIR/g1_29dof_spherehand_w_multi_boxes.xml"

if [[ ! -f "$TERRAIN_OBJ_FILE" ]]; then
    TERRAIN_OBJ_FILE="$DEMO_CLIMB_DIR/multi_boxes.obj"
fi

shopt -s nullglob
shopt -u nullglob

SCENE_XML_FILE="$DEFAULT_SCENE_XML_FILE"
if [[ "$TERRAIN_SCALE_FACTOR" == "0.7415730337078652" && -f "$SCALED_SCENE_XML_FILE" ]]; then
    SCENE_XML_FILE="$SCALED_SCENE_XML_FILE"
fi

if [[ ! -f "$SCENE_XML_FILE" ]]; then
    echo "Error: climbing scene xml not found: $SCENE_XML_FILE"
    exit 1
fi

if [[ ! -f "$TERRAIN_OBJ_FILE" ]]; then
    echo "Error: terrain object file not found: $TERRAIN_OBJ_FILE"
    exit 1
fi

if [[ "$SKIP_EXISTING" == "True" && -f "$RETARGETED_FILE" ]]; then
    echo "Skipping climbing retargeting because output already exists: $RETARGETED_FILE"
else
    echo "Running climbing retargeting..."
    python examples/robot_retarget.py \
        --data_path demo_data/climb \
        --task-type climbing \
        --task-name "$TASK_NAME" \
        --data_format mocap \
        --task-config.object-name "$OBJECT_NAME" \
        --robot-config.robot-urdf-file models/g1/g1_29dof_spherehand.urdf
fi

if [[ "$SKIP_EXISTING" == "True" && -f "$CONVERTED_FILE" ]]; then
    echo "Skipping climbing data conversion because output already exists: $CONVERTED_FILE"
else
    echo "Running climbing data conversion..."
    python data_conversion/convert_data_format_mj.py \
        --input_file "$RETARGETED_FILE" \
        --output_fps 50 \
        --output_name "converted_res/climbing/${TASK_NAME}_mj.npz" \
        --scene-xml-path "$SCENE_XML_FILE" \
        --data_format mocap \
        --object_name "$OBJECT_NAME" \
        --robot-config.robot-urdf-file models/g1/g1_29dof_spherehand.urdf \
        --once
fi

echo "Sourcing IsaacSim setup..."
cd "$PROJECT_ROOT"
unset CONDA_ENV_NAME
source "$PROJECT_ROOT/scripts/source_isaacsim_setup.sh"

# Ensure holosoma and isaaclab are installed in the IsaacSim env.
HOLOSOMA_DEPS_DIR="${HOLOSOMA_DEPS_DIR:-$HOME/.holosoma_deps}"
pip install -e "$PROJECT_ROOT/src/holosoma[unitree,booster]" --quiet
if ! python -c "import isaaclab" 2>/dev/null; then
    echo "isaaclab not found, reinstalling..."
    pip install 'setuptools<81' --quiet
    echo 'setuptools<81' > /tmp/hs-build-constraints.txt
    PIP_BUILD_CONSTRAINT=/tmp/hs-build-constraints.txt CMAKE_POLICY_VERSION_MINIMUM=3.5 \
        pip install -e "$HOLOSOMA_DEPS_DIR/IsaacLab/source/isaaclab" --quiet
    rm /tmp/hs-build-constraints.txt
fi

echo "Running terrain-aware whole-body tracking training..."
echo "Skip existing: $SKIP_EXISTING"
echo "Training num_envs: $TRAINING_NUM_ENVS"
echo "Training headless: $TRAINING_HEADLESS"
echo "Isaac env spacing: $ISAAC_ENV_SPACING"
echo "Terrain scale factor: $TERRAIN_SCALE_FACTOR"
echo "Init at random ep len: $INIT_AT_RANDOM_EP_LEN"
echo "Viewer tracking: $VIEWER_ENABLE_TRACKING"
echo "Viewer camera type: $VIEWER_CAMERA_TYPE"
echo "Viewer camera position: $VIEWER_CAMERA_POS"
echo "Viewer camera target: $VIEWER_CAMERA_TARGET"
echo "Scene xml: $SCENE_XML_FILE"
python src/holosoma/holosoma/train_agent.py \
    exp:g1-29dof-wbt \
    terrain:terrain-load-obj \
    logger:wandb \
    --command.setup_terms.motion_command.params.motion_config.motion_file="$CONVERTED_FILE" \
    simulator.config.viewer.camera:fixed-camera-config \
    logger.video.camera:fixed-camera-config \
    --terrain.terrain-term.obj-file-path="$TERRAIN_OBJ_FILE" \
    --training.num_envs="$TRAINING_NUM_ENVS" \
    --training.headless="$TRAINING_HEADLESS" \
    --simulator.config.scene.env_spacing="$ISAAC_ENV_SPACING" \
    --terrain.terrain-term.obj_scale="$TERRAIN_SCALE_FACTOR" \
    --simulator.config.viewer.enable_tracking="$VIEWER_ENABLE_TRACKING" \
    --simulator.config.viewer.camera.position="$VIEWER_CAMERA_POS_ARG" \
    --simulator.config.viewer.camera.target="$VIEWER_CAMERA_TARGET_ARG" \
    --logger.video.camera.position="$VIEWER_CAMERA_POS_ARG" \
    --logger.video.camera.target="$VIEWER_CAMERA_TARGET_ARG" \
    --algo.config.init_at_random_ep_len="$INIT_AT_RANDOM_EP_LEN"

echo "Done!"