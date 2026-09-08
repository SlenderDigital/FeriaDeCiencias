import cv2
import socket
import struct

from mediapipe_py.landmarker import Landmarker

import os
os.environ["QT_QPA_PLATFORM"] = "xcb"

STATUS_FILE = ".tracker.status"   # mismo archivo de fase que lee el juego

def _write_status(fase: str) -> None:
    try:
        with open(STATUS_FILE, "w") as f:
            f.write(fase)
    except OSError:
        pass

UDP_IP = "127.0.0.1"
UDP_PORT = 5005
sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)

landmarker = Landmarker()
landmarker.init()

cap = cv2.VideoCapture(0)
if not cap.isOpened():
    print("ERROR: no se pudo abrir la cámara /dev/video0", flush=True)
    _write_status("error:camera")
cap.set(cv2.CAP_PROP_FPS, 60)

_write_status("ready")

while cap.isOpened():
    success, image = cap.read()
    if not success:
        print("Ignoring empty camera frame.")
        continue

    # Convert to RGB for inference
    rgb_image = cv2.cvtColor(image, cv2.COLOR_BGR2RGB)
    rgb_image.flags.writeable = False

    landmarks_result = landmarker.process(rgb_image)

    # Process landmarks and network payload
    if landmarks_result:
        packed_landmarks = []
        for lm in landmarks_result:
            packed_landmarks.extend([lm[0], lm[1], lm[2]])

            # Draw landmark (assuming normalized coordinates 0.0 - 1.0)
            h, w, _ = image.shape
            cx, cy = int(lm[0] * w), int(lm[1] * h)
            cv2.circle(image, (cx, cy), 3, (0, 255, 0), -1)

        payload = struct.pack(
            f"<i{len(packed_landmarks)}f",
            len(landmarks_result),
            *packed_landmarks
        )

        sock.sendto(payload, (UDP_IP, UDP_PORT))
    else:
        payload = struct.pack(
            f"<i",
            0,
        )
        sock.sendto(payload, (UDP_IP, UDP_PORT))

    # Display window
    cv2.imshow("Landmark Tracking", cv2.flip(image, 1))

    # Press 'q' or ESC to exit
    key = cv2.waitKey(1) & 0xFF
    if key == ord('q') or key == 27:
        break

landmarker.shutdown()
cap.release()
cv2.destroyAllWindows()
sock.close()
