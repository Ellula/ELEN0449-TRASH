#!/bin/bash
#SBATCH --job-name=retrieve_images
#SBATCH --time=0-05:00:00
#SBATCH --ntasks=1
#SBATCH --mem=64G
#SBATCH --gres=gpu:1
#SBATCH --output=resultats/resultats_%j.txt # %j = Job ID classique
#SBATCH --error=resultats/logs_%j.txt

# On crée le dossier global 'output' s'il n'existe pas
mkdir -p output

# On parcourt les fichiers JSON qu'on vient d'importer depuis le Mac
for file in ~/cvu/images_a_annoter/*.sam_prompts.json; do
    
    # Sécurité au cas où le dossier serait vide
    [ -e "$file" ] || continue

    # On isole le nom complet du fichier
    filename=$(basename "$file")

    # On extrait le nom du projet (tout ce qui est avant "_frame_")
    # -> Donne : project-S2_V1
    project_name="${filename%_frame_*}"

    # On extrait le nom de la frame (tout ce qui est après le nom du projet + "_")
    # -> Donne : frame_00015.sam_prompts.json
    frame_name="${filename#${project_name}_}"

    # On crée le bon sous-dossier de destination (ex: output/project-S2_V1)
    mkdir -p "output/${project_name}"

    # On déplace le fichier au bon endroit et on le renomme proprement
    mv "$file" "output/${project_name}/$frame_name"

    echo "✅ Rangé : $frame_name dans output/${project_name}/"
done

echo "------------------------------------------------"
echo "🎉 Terminé ! Tous tes fichiers sont triés dans le dossier output/."