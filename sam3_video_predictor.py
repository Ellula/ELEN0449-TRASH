import os
import cv2
import matplotlib.pyplot as plt
import numpy as np
import torch
import gc
from sam3.model_builder import build_sam3_video_predictor
from sam3.visualization_utils import (
    prepare_masks_for_visualization,
    visualize_formatted_frame_output,
)

# --- UTILS FOR CHUNKING ---

def split_video_into_chunks(input_path, chunk_size=100, output_dir="temp_chunks"):
    """Splits the video into smaller .mp4 files to save VRAM."""
    if not os.path.exists(output_dir):
        os.makedirs(output_dir)
    cap = cv2.VideoCapture(input_path)
    fps = cap.get(cv2.CAP_PROP_FPS)
    width = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
    height = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
    fourcc = cv2.VideoWriter_fourcc(*'mp4v')
    
    chunk_paths = []
    chunk_idx, frame_count = 0, 0
    out = None
    
    while True:
        ret, frame = cap.read()
        if not ret: break
        if frame_count % chunk_size == 0:
            if out: out.release()
            chunk_path = os.path.join(output_dir, f"chunk_{chunk_idx:03d}.mp4")
            out = cv2.VideoWriter(chunk_path, fourcc, fps, (width, height))
            chunk_paths.append(chunk_path)
            chunk_idx += 1
        out.write(frame)
        frame_count += 1
    if out: out.release()
    cap.release()
    return chunk_paths

def get_bbox_from_output(frame_output):
    """Extracts a bounding box from the prediction mask to use as a prompt for the next chunk."""
    # SAM3 outputs often contain 'mask' or 'segmentation' in a list of dicts
    # Adjust the keys based on your specific SAM3 version output
    try:
        mask = frame_output[0]['mask'] 
        if isinstance(mask, torch.Tensor):
            mask = mask.cpu().numpy()
        
        y_indices, x_indices = np.where(mask > 0)
        if len(x_indices) == 0: return None
        return [int(np.min(x_indices)), int(np.min(y_indices)), 
                int(np.max(x_indices)), int(np.max(y_indices))]
    except:
        return None

# --- MAIN EXECUTION ---

if __name__ == "__main__":
    predictor = build_sam3_video_predictor(gpus_to_use=list(range(torch.cuda.device_count())))
    video_path = "../cvu/data/S0_V2.mp4"
    
    # 1. Split video into chunks (e.g., 100 frames each)
    chunk_paths = split_video_into_chunks(video_path, chunk_size=50)
    
    combined_outputs = {}
    full_video_frames = [] # For final visualization
    current_frame_offset = 0
    last_bbox = None
    prompt_text_str = "glass bottle;"

    for i, chunk_path in enumerate(chunk_paths):
        print(f"Processing chunk {i+1}/{len(chunk_paths)}...")
        
        # Load frames for visualization
        cap = cv2.VideoCapture(chunk_path)
        chunk_frames = []
        while True:
            ret, frame = cap.read()
            if not ret: break
            chunk_frames.append(cv2.cvtColor(frame, cv2.COLOR_BGR2RGB))
        cap.release()
        full_video_frames.extend(chunk_frames)

        # Start session for current chunk
        gc.collect()
        torch.cuda.empty_cache()
        
        response = predictor.handle_request(dict(
            type="start_session", resource_path=chunk_path,
            offload_video_to_cpu=True, offload_state_to_cpu=True
        ))
        session_id = response["session_id"]

        # Add Prompt: Text for first chunk, BBox for subsequent chunks
        if i == 0:
            predictor.handle_request(dict(
                type="add_prompt", session_id=session_id, frame_index=0, text=prompt_text_str
            ))
        elif last_bbox:
            predictor.handle_request(dict(
                type="add_prompt", session_id=session_id, frame_index=0, 
                bounding_boxes=[last_bbox], clear_old_boxes=True
            ))

        # Propagate within this chunk
        chunk_outputs = {}
        for resp in predictor.handle_stream_request(dict(type="propagate_in_video", session_id=session_id)):
            f_idx = resp["frame_index"]
            chunk_outputs[f_idx] = resp["outputs"]
            # Save to global dictionary with absolute frame index
            combined_outputs[current_frame_offset + f_idx] = resp["outputs"]

        # Get the BBox of the very last frame for the next chunk's relay
        last_frame_idx = max(chunk_outputs.keys())
        last_bbox = get_bbox_from_output(chunk_outputs[last_frame_idx])
        
        current_frame_offset += len(chunk_frames)
        
        # Cleanup session
        predictor.handle_request(dict(type="reset_session", session_id=session_id))

    # --- VISUALIZATION & VIDEO GEN ---
    
    print("Preparing visualization...")
    formatted_outputs = prepare_masks_for_visualization(combined_outputs)
    
    output_video_path = "resultat_tracking_chunked.mp4"
    h, w, _ = full_video_frames[0].shape
    out_video = cv2.VideoWriter(output_video_path, cv2.VideoWriter_fourcc(*'mp4v'), 30.0, (w, h))

    for frame_idx in range(len(formatted_outputs)):
        visualize_formatted_frame_output(
            frame_idx, full_video_frames, outputs_list=[formatted_outputs],
            titles=[""], figsize=(w / 100, h / 100)
        )
        fig = plt.gcf()
        fig.canvas.draw()
        img_array = np.frombuffer(fig.canvas.tostring_rgb(), dtype=np.uint8)
        img_array = img_array.reshape((fig.canvas.get_width_height()[::-1] + (3,)))
        out_video.write(cv2.resize(cv2.cvtColor(img_array, cv2.COLOR_RGB2BGR), (w, h)))
        plt.close(fig)

    out_video.release()
    print(f"Success: {output_video_path}")
