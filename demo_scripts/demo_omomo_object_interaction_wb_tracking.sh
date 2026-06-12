#!/usr/bin/env bash

# Script for running retargeting, data conversion, and whole-body tracking training
# for OMOMO object interaction sequences.
# Requires Ubuntu/Linux OS (IsaacSim is not supported on Mac)

set -e  # Exit on error

# figure out where this file is located even if it is being run from another location
# or as a symlink
SOURCE="${BASH_SOURCE[0]:-${(%):-%x}}"
while [ -h "$SOURCE" ]; do # resolve $SOURCE until the file is no longer a symlink
  DIR="$( cd -P "$( dirname "$SOURCE" )" >/dev/null && pwd )"
  SOURCE="$(readlink "$SOURCE")"
  [[ $SOURCE != /* ]] && SOURCE="$DIR/$SOURCE" # if $SOURCE was a relative symlink, resolve from symlink dir
done
SCRIPT_DIR="$( cd -P "$( dirname "$SOURCE" )" >/dev/null && pwd )"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

TASK_NAME="sub3_largebox_003"
OBJECT_NAME="largebox"
TRAINING_NUM_ENVS="${TRAINING_NUM_ENVS:-4096}"
TRAINING_HEADLESS="${TRAINING_HEADLESS:-True}"
ISAAC_ENV_SPACING="${ISAAC_ENV_SPACING:-2.5}"
INIT_AT_RANDOM_EP_LEN="${INIT_AT_RANDOM_EP_LEN:-False}"
LOGGER_PRESET="${LOGGER_PRESET:-disabled}"
VIEWER_ENABLE_TRACKING="${VIEWER_ENABLE_TRACKING:-True}"
VIEWER_CAMERA_TYPE="${VIEWER_CAMERA_TYPE:-fixed}"
VIEWER_CAMERA_POS="${VIEWER_CAMERA_POS:-2.5,-2.5,1.6}"
VIEWER_CAMERA_TARGET="${VIEWER_CAMERA_TARGET:-0.0,0.0,0.8}"
VIDEO_ENABLED="${VIDEO_ENABLED:-False}"
VIDEO_INTERVAL="${VIDEO_INTERVAL:-200}"
VIDEO_WIDTH="${VIDEO_WIDTH:-1280}"
VIDEO_HEIGHT="${VIDEO_HEIGHT:-720}"
VIDEO_UPLOAD_TO_WANDB="${VIDEO_UPLOAD_TO_WANDB:-False}"
VIDEO_SAVE_DIR="${VIDEO_SAVE_DIR:-$PROJECT_ROOT/logs/object_interaction_videos}"


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

# # Source retargeting setup script (for retargeting and data conversion)
# echo "Sourcing retargeting setup..."
# source "$PROJECT_ROOT/scripts/source_retargeting_setup.sh"

# # Ensure holosoma_retargeting is installed with correct dependencies (e.g. numpy version)
# pip install -e "$PROJECT_ROOT/src/holosoma_retargeting" --quiet

# Change to retargeting directory
RETARGET_DIR="$PROJECT_ROOT/src/holosoma_retargeting/holosoma_retargeting"
cd "$RETARGET_DIR"

# # Step 1: Run retargeting
# echo "Running object-interaction retargeting..."
# python examples/robot_retarget.py \
#     --data_path demo_data/OMOMO_new \
#     --task-type object_interaction \
#     --task-name "$TASK_NAME" \
#     --data_format smplh

# # Step 2: Run data conversion
# echo "Running data conversion with dynamic object..."
RETARGETED_FILE="./demo_results/g1/object_interaction/omomo/${TASK_NAME}_original.npz"
CONVERTED_FILE="$RETARGET_DIR/converted_res/object_interaction/${TASK_NAME}_mj_w_obj.npz"
python data_conversion/convert_data_format_mj.py \
    --input_file "$RETARGETED_FILE" \
    --output_fps 50 \
    --output_name "converted_res/object_interaction/${TASK_NAME}_mj_w_obj.npz" \
    --data_format smplh \
    --object_name "$OBJECT_NAME" \
    --has_dynamic_object \
    --once

# Step 3: Source IsaacSim setup script (for whole-body tracking training)
echo "Sourcing IsaacSim setup..."
cd "$PROJECT_ROOT"
unset CONDA_ENV_NAME
source "$PROJECT_ROOT/scripts/source_isaacsim_setup.sh"

# Ensure holosoma and isaaclab are installed in the IsaacSim env
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

# Step 4: Run whole-body tracking training
echo "Running object-aware whole-body tracking training..."
echo "Logger preset: $LOGGER_PRESET"
echo "Training num_envs: $TRAINING_NUM_ENVS"
echo "Training headless: $TRAINING_HEADLESS"
echo "Isaac env spacing: $ISAAC_ENV_SPACING"
echo "Init at random ep len: $INIT_AT_RANDOM_EP_LEN"
echo "Viewer tracking: $VIEWER_ENABLE_TRACKING"
echo "Viewer camera type: $VIEWER_CAMERA_TYPE"
echo "Viewer camera position: $VIEWER_CAMERA_POS"
echo "Viewer camera target: $VIEWER_CAMERA_TARGET"
echo "Video enabled: $VIDEO_ENABLED"
echo "Video interval: $VIDEO_INTERVAL"
python src/holosoma/holosoma/train_agent.py \
    exp:g1-29dof-wbt-w-object \
    logger:wandb \
    --command.setup_terms.motion_command.params.motion_config.motion_file="$CONVERTED_FILE" \
    simulator.config.viewer.camera:fixed-camera-config \
    --training.num_envs="$TRAINING_NUM_ENVS" \
    --training.headless="$TRAINING_HEADLESS" \
    --simulator.config.scene.env_spacing="$ISAAC_ENV_SPACING" \
    --simulator.config.viewer.enable_tracking="$VIEWER_ENABLE_TRACKING" \
    --simulator.config.viewer.camera.position="$VIEWER_CAMERA_POS_ARG" \
    --simulator.config.viewer.camera.target="$VIEWER_CAMERA_TARGET_ARG" \
    --algo.config.init_at_random_ep_len="$INIT_AT_RANDOM_EP_LEN"

echo "Done!"