#!/bin/bash
#SBATCH --job-name=retrieve_images
#SBATCH --time=0-05:00:00
#SBATCH --ntasks=1
#SBATCH --mem=64G
#SBATCH --gres=gpu:1
#SBATCH --output=resultats/resultats_%j.txt
#SBATCH --error=resultats/logs_%j.txt

# Script 5

# Organize the JSON files into the project folders 

mkdir -p output

# We go through the JSON files that we just imported from the computer
for file in ~/cvu/images_to_annote/*.sam_prompts.json; do
    
    [ -e "$file" ] || continue

    # We isolate the file name
    filename=$(basename "$file")

    # We isolate the folder name
    project_name="${filename%_frame_*}"

    # We isolate the frame name
    frame_name="${filename#${project_name}_}"

    # Create the folder if needed
    mkdir -p "output/${project_name}"

    # Move the file to the right folder and rename it
    mv "$file" "output/${project_name}/$frame_name"

    echo " $frame_name is in output/${project_name}/"
done

echo "All the files are organized in the output folder."
