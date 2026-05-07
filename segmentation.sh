#!/bin/bash
#SBATCH --job-name=mesh_segmentation_array
#SBATCH --time=0-04:00:00
#SBATCH --ntasks=1
#SBATCH --mem=64G
#SBATCH --gres=gpu:1
#SBATCH --array=0-17%5
#SBATCH --output=resultats/resultats_seg_%A_%a.txt
#SBATCH --error=resultats/logs_seg_%A_%a.txt
#SBATCH --nodelist=compute-01
#SBATCH --mail-user=mae.klinkenberg@student.uliege.be
#SBATCH --mail-type=END,FAIL

# Script 6

set -e

echo "Start of the script - Task ID: $SLURM_ARRAY_TASK_ID"

# Environment activation
eval "$(/home/mklinkenberg/.local/bin/micromamba shell hook --shell bash)"
export MAMBA_ROOT_PREFIX=~/micromamba/
micromamba activate mesh_splatting

DATA_DIR="$(pwd)/data" 
OUTPUT_DIR="$(pwd)/output"
export PYTHONUNBUFFERED=1

export PYTORCH_CUDA_ALLOC_CONF=expandable_segments:True

# We move into mesh-splatting
cd mesh-splatting
PT_LARGE_MODEL_PATH="/home/mklinkenberg/cvu/sam2/sam2.1_hiera_large.pt"
PT_BASE_MODEL_PATH="/home/mklinkenberg/cvu/sam2/sam2.1_hiera_base_plus.pt"

# We select the right project folder
shopt -s nullglob
FOLDERS=(
    "$DATA_DIR"/project-S[1-2]_*
    "$DATA_DIR/project-S3_V1"
    "$DATA_DIR"/project-S[4-5]_*
)
shopt -u nullglob
PROJECT_PATH="${FOLDERS[$SLURM_ARRAY_TASK_ID]}"

# Security
if [ -z "$PROJECT_PATH" ] || [ ! -d "$PROJECT_PATH" ]; then
    echo "End: No folder found for task n°$SLURM_ARRAY_TASK_ID"
    exit 0
fi

if [[ "$PROJECT_PATH" == "$DATA_DIR"/project-S[1-2]_* ]] || \
    [[ "$PROJECT_PATH" == "$DATA_DIR"/project-S3_V1 ]] || \
    [[ "$PROJECT_PATH" == "$DATA_DIR"/project-S[4-5]_* ]]; then
        PT_MODEL_PATH="$PT_LARGE_MODEL_PATH"
else
    PT_MODEL_PATH="$PT_BASE_MODEL_PATH"

fi

# We create a link because we are in mesh-splatting and not in sam2
if [ -f "$PT_MODEL_PATH" ]; then
    ln -sf "$PT_MODEL_PATH" .
else
    echo "Error : The file $PT_MODEL_PATH doesn't exist."
    exit 1
fi

NAME_SCENE=$(basename "$PROJECT_PATH")
MODEL_PATH="$OUTPUT_DIR/$NAME_SCENE"

echo "CLONE $SLURM_ARRAY_TASK_ID : START OF PROCESSING FOR $NAME_SCENE"

# Verify if there is a JSON
JSON_FILE=$(ls "$MODEL_PATH"/*.sam_prompts.json 2>/dev/null | head -n 1)

if [ -z "$JSON_FILE" ]; then
    echo "JSON file not found for $NAME_SCENE. Stop."
    exit 0
fi

echo "JSON file found: $(basename "$JSON_FILE")"

MASKS_DIR="$MODEL_PATH/masks"

echo " Cleaning of the previous attempts"
rm -rf "$MASKS_DIR"
rm -f "$MODEL_PATH"/*.ply
rm -f mesh.ply

mkdir -p "$MASKS_DIR"
IMAGES_DIR="$PROJECT_PATH/images" 

echo " Extraction of the images"
python -m segmentation.extract_images -s "$PROJECT_PATH" -m "$MODEL_PATH" --eval

echo " Generate masks with SAM"
TMP_DIR="tmp_sam_${SLURM_ARRAY_TASK_ID}"
rm -rf "$TMP_DIR"
mkdir -p "$TMP_DIR"
python -m segmentation.sam_mask_generator_json --data_path "$IMAGES_DIR" --save_path "$MASKS_DIR" --json_path "$JSON_FILE" --tmp_dir "$TMP_DIR"

# We extract the IDs from the JSON
OBJECT_IDS=$(python -c "
import json, sys
try:
    data = json.load(open(sys.argv[1]))
    if isinstance(data, list):
        print(' '.join(str(obj.get('object_id', i+1)).replace('object_', '') for i, obj in enumerate(data)))
    elif isinstance(data, dict):
        print(' '.join(str(k).replace('object_', '') for k in data.keys()))
except Exception:
    print('1')
" "$JSON_FILE")

echo " Objects to process: $OBJECT_IDS"

TOTAL_IDS=$(echo "$OBJECT_IDS" | wc -w)
COUNT=0

# For each object
for OBJECT_ID in $OBJECT_IDS; do
    COUNT=$((COUNT + 1))
    echo "   Processing object : $OBJECT_ID"

    echo "  Identification of triangles"
    python -m segmentation.segment -s "$PROJECT_PATH" -m "$MODEL_PATH" --eval --path_mask "$MASKS_DIR" --object_id "$OBJECT_ID"
    
    echo "   Filtering and rendering"
    if [ "$COUNT" -eq "$TOTAL_IDS" ]; then
        python -m segmentation.run_single_object -s "$PROJECT_PATH" -m "$MODEL_PATH" --eval --ratio_threshold 0.60
    else
        python -m segmentation.run_single_object -s "$PROJECT_PATH" -m "$MODEL_PATH" --eval --ratio_threshold 0.90
    fi
    
    echo "   Creation PLY file"
    python -m segmentation.create_ply "$MODEL_PATH" --out "$MODEL_PATH/mesh.ply"

    if [ -f "$MODEL_PATH/mesh.ply" ]; then
        mv "$MODEL_PATH/mesh.ply" "$MODEL_PATH/${NAME_SCENE}_object_${OBJECT_ID}.ply"
        echo "     Save object : ${NAME_SCENE}_object_${OBJECT_ID}.ply"
    else
        echo "    Error: The PLY file was not generated in $MODEL_PATH."
        exit 1
    fi

done

echo "END OF $NAME_SCENE"
