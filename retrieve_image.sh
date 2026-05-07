#!/bin/bash
#SBATCH --job-name=annotate_points
#SBATCH --time=0-05:00:00
#SBATCH --ntasks=1
#SBATCH --mem=64G
#SBATCH --gres=gpu:1
#SBATCH --output=resultats/resultats_%j.txt # %j = Job ID classique
#SBATCH --error=resultats/logs_%j.txt
#SBATCH --mail-user=mae.klinkenberg@student.uliege.be
#SBATCH --mail-type=END,FAIL 

# Script 4

# On crée un dossier temporaire pour mettre les images
mkdir -p images_a_annoter

projects=()
for s in {1..8}; do
    projects+=("project-S${s}_V1" "project-S${s}_V2")
done
projects+=("project-S9_V1" "project-S2_V3")

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
        # On copie l'image en lui donnant le nom du projet pour ne pas les mélanger
        cp "$img_path" "images_a_annoter/${proj}_frame_${frame_number}.png"
    fi
done

# On compresse le dossier
zip -r images_a_annoter.zip images_a_annoter/
echo "✅ C'est prêt ! Le fichier images_a_annoter.zip contient uniquement tes 18 images."