#!/bin/bash
#SBATCH --job-name=annotate_points
#SBATCH --time=0-05:00:00
#SBATCH --ntasks=1
#SBATCH --mem=64G
#SBATCH --gres=gpu:1
#SBATCH --output=resultats/resultats_%j.txt
#SBATCH --error=resultats/logs_%j.txt
#SBATCH --mail-user=mae.klinkenberg@student.uliege.be
#SBATCH --mail-type=END,FAIL 

# Script 4

# Take only the images to annote it and zip it to transfer to my computer 
# because Alan doesn't support graphical user interfaces

mkdir -p images_to_annote

projects=()
for s in {1..8}; do
    projects+=("project-S${s}_V1" "project-S${s}_V2")
done
projects+=("project-S9_V1" "project-S2_V3")

# We take a frame with all the wastes and at least one object of reference
for proj in "${projects[@]}"; do
    frame_number="00001"
    case "$proj" in
        "project-S1_V1") frame_number="00052" ;;
        "project-S2_V1") frame_number="00015" ;;
        "project-S2_V2") frame_number="00010" ;;
        "project-S2_V3") frame_number="00010" ;;
        "project-S3_V1") frame_number="00020" ;;
        "project-S4_V2") frame_number="00060" ;;
        "project-S5_V1") frame_number="00056" ;;
        "project-S8_V2") frame_number="00087" ;;
    esac

    img_path="data/${proj}/images/frame_${frame_number}.png"

    if [ -f "$img_path" ]; then
        # Copy the image and rename it to avoid confusion
        cp "$img_path" "images_to_annote/${proj}_frame_${frame_number}.png"
    fi
done

# Zip the folder
zip -r images_to_annote.zip images_to_annote/
echo "The file images_to_annote.zip contains the 18 frames."
