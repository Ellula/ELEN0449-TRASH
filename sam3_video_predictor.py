import os
import sys
import importlib
import glob
import cv2
import matplotlib.pyplot as plt
import numpy as np
from PIL import Image
import torch
import gc

# # --- 1. pkg_resources Mock ---
# class SmartPkgResources:
#     def __init__(self):
#         self.__file__ = __file__

#     def resource_filename(self, package_name, resource_name):
#         try:
#             module = importlib.import_module(package_name)
#             package_path = os.path.dirname(module.__file__)
#             actual_path = os.path.join(package_path, resource_name)
#             print(f"File found and redirected: {actual_path}")
#             return actual_path
#         except ImportError:
#             print(f"Error: Could not import package {package_name}")
#             return ""

# # Inject the mock before importing SAM3 components
# sys.modules["pkg_resources"] = SmartPkgResources()

# --- 2. SAM3 Specific Imports ---
from sam3.model_builder import build_sam3_video_predictor
from sam3.visualization_utils import (
    load_frame,
    prepare_masks_for_visualization,
    visualize_formatted_frame_output,
)

# --- 3. Configuration & Plot Settings ---
plt.rcParams["axes.titlesize"] = 12
plt.rcParams["figure.titlesize"] = 12

if torch.cuda.is_available():
    gpus_to_use = list(range(torch.cuda.device_count()))
else:
    gpus_to_use = []

# --- 4. Utility Functions ---
def propagate_in_video(predictor, session_id):
    """Propagate masks from frame 0 to the end of the video."""
    outputs_per_frame = {}
    for response in predictor.handle_stream_request(
        request=dict(type="propagate_in_video", session_id=session_id)
    ):
        outputs_per_frame[response["frame_index"]] = response["outputs"]
    return outputs_per_frame

# --- 5. Main Execution ---
if __name__ == "__main__":
    predictor = build_sam3_video_predictor(gpus_to_use=gpus_to_use)
    video_path = "../cvu/data/S0_V1.mp4"

    # Load video frames for visualization
    if isinstance(video_path, str) and video_path.endswith(".mp4"):
        cap = cv2.VideoCapture(video_path)
        video_frames_for_vis = []
        while True:
            ret, frame = cap.read()
            if not ret:
                break
            video_frames_for_vis.append(cv2.cvtColor(frame, cv2.COLOR_BGR2RGB))
        cap.release()
    else:
        video_frames_for_vis = glob.glob(os.path.join(video_path, "*.jpg"))
        video_frames_for_vis.sort()

    gc.collect()
    torch.cuda.empty_cache()

    # Start Session
    response = predictor.handle_request(
        request=dict(
            type="start_session",
            resource_path=video_path,
            offload_video_to_cpu=True,
            offload_state_to_cpu=True,
        )
    )
    session_id = response["session_id"]

    # Reset Session
    _ = predictor.handle_request(
        request=dict(type="reset_session", session_id=session_id)
    )

    # Add Text Prompt
    prompt_text_str = "glass bottle;"
    response = predictor.handle_request(
        request=dict(
            type="add_prompt",
            session_id=session_id,
            frame_index=0,
            text=prompt_text_str,
        )
    )
    
    # Propagate and Prepare Visualization
    outputs_per_frame = propagate_in_video(predictor, session_id)
    outputs_per_frame = prepare_masks_for_visualization(outputs_per_frame)

    # --- 6. Video Generation ---
    output_video_path = "resultat_tracking.mp4"
    
    height, width, _ = video_frames_for_vis[0].shape
    fps = 30.0 
    
    fourcc = cv2.VideoWriter_fourcc(*'mp4v')
    out_video = cv2.VideoWriter(output_video_path, fourcc, fps, (width, height))

    print("Generating video file...")
    plt.close("all")

    for frame_idx in range(len(outputs_per_frame)):
        visualize_formatted_frame_output(
            frame_idx,
            video_frames_for_vis,
            outputs_list=[outputs_per_frame],
            titles=[""], 
            figsize=(width / 100, height / 100), 
        )
        
        fig = plt.gcf()
        fig.set_dpi(100)
        fig.tight_layout(pad=0) 
        
        fig.canvas.draw()
        img_array = np.frombuffer(fig.canvas.tostring_rgb(), dtype=np.uint8)
        
        h_canvas, w_canvas = fig.canvas.get_width_height()[::-1]
        img_array = img_array.reshape((h_canvas, w_canvas, 3))
        
        # Convert RGB to BGR and resize to match VideoWriter exactly
        img_bgr = cv2.cvtColor(img_array, cv2.COLOR_RGB2BGR)
        img_bgr_resized = cv2.resize(img_bgr, (width, height))
        
        out_video.write(img_bgr_resized)
        plt.close(fig)

    out_video.release()
    print(f"Video successfully generated: {output_video_path}")
