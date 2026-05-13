import os
import torch
import numpy as np
import trimesh
from PIL import Image
from sam3.model_builder import build_sam3_image_model
from sam3.model.sam3_image_processor import Sam3Processor

def run_sam3_extraction(ply_path, text_prompt, output_path="extracted.ply"):
    print(f"Loading mesh: {ply_path}...")
    mesh = trimesh.load(ply_path)
    
    scene = mesh.scene()
    images = []
    transforms = []
    
    print("Rendering batch of views...")
    for angle in [0, np.pi/2, np.pi]:
        # Rotate camera around the scene
        rotation = trimesh.transformations.rotation_matrix(angle, [0, 1, 0])
        scene.camera_transform = rotation @ scene.camera_transform
        
        # Render to image (Returns bytes)
        data = scene.save_image(resolution=(1024, 1024))
        img = Image.open(trimesh.util.wrap_as_stream(data)).convert("RGB")
        images.append(img)
        transforms.append(scene.camera_transform.copy())

    device = "cuda" if torch.cuda.is_available() else "cpu"
    model = build_sam3_image_model()
    
    print(f"Running SAM 3 inference for prompt: '{text_prompt}'...")
    batch_results = predictor.predict_batch(
        images=images,
        text_prompts=[text_prompt] * len(images),
        multimask_output=False
    )

    all_selected_indices = set()
    
    vertices = mesh.vertices
    for i, res in enumerate(batch_results):
        mask = res['masks'][0] # (1024, 1024) boolean array
        
        # Project 3D points to the 2D plane of view 'i'
        # This uses the scene's camera projection matrix
        coords_2d, visible = scene.camera.project(vertices, transform=transforms[i])
        
        # Scale coords to pixel space
        coords_2d = ((coords_2d + 1.0) * 512).astype(int)
        
        # Check which vertices fall inside the 'True' area of the SAM 3 mask
        for idx, (x, y) in enumerate(coords_2d):
            if 0 <= x < 1024 and 0 <= y < 1024:
                if mask[y, x]:
                    all_selected_indices.add(idx)

    # 5. Export result
    if all_selected_indices:
        new_mesh = mesh.submesh([list(all_selected_indices)], append=True)
        new_mesh.export(output_path)
        print(f"Successfully extracted {len(all_selected_indices)} vertices to {output_path}")
    else:
        print("No objects found matching the prompt.")

# Execution
if __name__ == "__main__":
    run_sam3_extraction(
        ply_path="project-S1_V1_mesh.ply", 
        text_prompt="" 
    )