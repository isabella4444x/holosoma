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
ISAAC_ENV_SPACING="${ISAAC_ENV_SPACING:-0.0}"
INIT_AT_RANDOM_EP_LEN="${INIT_AT_RANDOM_EP_LEN:-False}"
VIEWER_ENABLE_TRACKING="${VIEWER_ENABLE_TRACKING:-True}"

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

RETARGETED_FILE="./demo_results/g1/climbing/mocap_climb/${TASK_NAME}_original.npz"
CONVERTED_FILE="$RETARGET_DIR/converted_res/climbing/${TASK_NAME}_mj.npz"
TERRAIN_OBJ_FILE="$RETARGET_DIR/demo_data/climb/${TASK_NAME}/multi_boxes.obj"

if [[ ! -f "$TERRAIN_OBJ_FILE" ]]; then
    echo "Error: terrain object file not found: $TERRAIN_OBJ_FILE"
    exit 1
fi

echo "Running climbing retargeting..."
python examples/robot_retarget.py \
    --data_path demo_data/climb \
    --task-type climbing \
    --task-name "$TASK_NAME" \
    --data_format mocap \
    --task-config.object-name "$OBJECT_NAME" \
    --robot-config.robot-urdf-file models/g1/g1_29dof_spherehand.urdf

echo "Running climbing data conversion..."
python data_conversion/convert_data_format_mj.py \
    --input_file "$RETARGETED_FILE" \
    --output_fps 50 \
    --output_name "converted_res/climbing/${TASK_NAME}_mj.npz" \
    --data_format mocap \
    --object_name "$OBJECT_NAME" \
    --once

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
echo "Training num_envs: $TRAINING_NUM_ENVS"
echo "Training headless: $TRAINING_HEADLESS"
echo "Isaac env spacing: $ISAAC_ENV_SPACING"
echo "Init at random ep len: $INIT_AT_RANDOM_EP_LEN"
python src/holosoma/holosoma/train_agent.py \
    exp:g1-29dof-wbt \
    terrain:terrain-load-obj \
    logger:wandb \
    --command.setup_terms.motion_command.params.motion_config.motion_file="$CONVERTED_FILE" \
    --terrain.terrain-term.obj-file-path="$TERRAIN_OBJ_FILE" \
    --training.num_envs="$TRAINING_NUM_ENVS" \
    --training.headless="$TRAINING_HEADLESS" \
    --simulator.config.scene.env_spacing="$ISAAC_ENV_SPACING" \
    --simulator.config.viewer.enable_tracking="$VIEWER_ENABLE_TRACKING" \
    --algo.config.init_at_random_ep_len="$INIT_AT_RANDOM_EP_LEN"

echo "Done!"