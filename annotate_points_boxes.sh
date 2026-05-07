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

eval "$(/home/mklinkenberg/.local/bin/micromamba shell hook --shell bash)"
export MAMBA_ROOT_PREFIX=~/micromamba/
micromamba activate mesh_splatting

export SDL_AUDIODRIVER=dummy

# 1. On définit UNIQUEMENT la liste des projets spécifiques
projects=(
    "project-S2_V1"
    "project-S3_V1"
    "project-S4_V2"
    "project-S5_V1"
    "project-S8_V2"
)

# 2. Boucle sur chaque projet de cette nouvelle liste restreinte
for proj in "${projects[@]}"; do
    
    # 3. Récupération du bon numéro de frame
    case "$proj" in
        "project-S2_V1") frame_number="00015" ;;
        "project-S3_V1") frame_number="00020" ;;
        "project-S4_V2") frame_number="00060" ;;
        "project-S5_V1") frame_number="00056" ;;
        "project-S8_V2") frame_number="00087" ;;
    esac

    # Construction du chemin de l'image
    img_path="data/${proj}/images/frame_${frame_number}.png"

    # Vérification de l'existence du fichier avant de lancer le script Python
    if [ -f "$img_path" ]; then
        echo "Lancement de l'extraction pour : $img_path"
        
        # Lance le script Python
        python mesh-splatting/annotate_points_boxes.py "$img_path"
        
        # Définition du chemin du fichier JSON généré par défaut par Python
        json_path="data/${proj}/images/frame_${frame_number}.sam_prompts.json"
        
        # Vérifie si l'annotation a bien été sauvegardée
        if [ -f "$json_path" ]; then
            # Crée le dossier de destination s'il n'existe pas
            mkdir -p "output/${proj}"
            
            # Déplace le fichier JSON vers le nouveau dossier
            mv "$json_path" "output/${proj}/"
            echo "Annotation déplacée dans : output/${proj}/"
        else
            echo "Aucune annotation sauvegardée pour $proj."
        fi

    else
        echo "Attention : Fichier introuvable -> $img_path (ignoré)"
    fi

done
