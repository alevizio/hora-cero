"""Dev-only, for the website: a turntable's frames (tools/dev/turntable.gd) made into the site's files: a looping
VP9 .webm with alpha (Chrome, Firefox), a looping HEVC .mov with alpha (Safari), and a still .webp of the
three-quarter view for reduced motion and as the videos' poster. Every frame is cropped to the box all of them fill
(so the figure never jumps), with a small margin, and scaled to the height asked for.
usage: turntable_encode.py <frames dir> <out prefix> <height> [still frame]
       writes <out prefix>.webm, <out prefix>.mov, <out prefix>-still.webp and prints their sizes."""
import glob
import os
import subprocess
import sys
import tempfile

from PIL import Image

FPS = 24
MARGIN = 6


def main():
    frames_dir, prefix, height = sys.argv[1], sys.argv[2], int(sys.argv[3])
    frames = sorted(glob.glob(os.path.join(frames_dir, "f_*.png")))
    still_at = int(sys.argv[4]) if len(sys.argv) > 4 else len(frames) // 8
    images = [Image.open(f).convert("RGBA") for f in frames]
    # the box every frame's figure fits in (alpha above a whisper: the contact shadow's faint edge is kept out)
    boxes = [im.getchannel("A").point(lambda a: 255 if a > 10 else 0).getbbox() for im in images]
    left = max(0, min(b[0] for b in boxes) - MARGIN)
    top = max(0, min(b[1] for b in boxes) - MARGIN)
    right = min(images[0].width, max(b[2] for b in boxes) + MARGIN)
    bottom = min(images[0].height, max(b[3] for b in boxes) + MARGIN)
    scale = height / (bottom - top)
    width = int(round((right - left) * scale / 2)) * 2
    with tempfile.TemporaryDirectory() as tmp:
        for k, im in enumerate(images):
            im.crop((left, top, right, bottom)).resize((width, height), Image.LANCZOS).save(os.path.join(tmp, "f_%03d.png" % k))
        src = ["-framerate", str(FPS), "-i", os.path.join(tmp, "f_%03d.png")]
        run = lambda args: subprocess.run(["ffmpeg", "-v", "error", "-y"] + src + args, check=True)
        # VP9 keeps alpha only as yuva420p, and libvpx wants alt-ref frames off for it
        run(["-c:v", "libvpx-vp9", "-pix_fmt", "yuva420p", "-b:v", "0", "-crf", "42", "-auto-alt-ref", "0",
             "-row-mt", "1", "-an", prefix + ".webm"])
        # Safari plays alpha from HEVC in a QuickTime file (hvc1), made by VideoToolbox
        run(["-c:v", "hevc_videotoolbox", "-allow_sw", "1", "-alpha_quality", "0.75", "-b:v", "600k", "-tag:v", "hvc1",
             "-an", prefix + ".mov"])
        Image.open(os.path.join(tmp, "f_%03d.png" % still_at)).save(prefix + "-still.webp", quality=86, method=6)
    for ext in (".webm", ".mov", "-still.webp"):
        print("%s%s %dx%d %d KB" % (os.path.basename(prefix), ext, width, height, os.path.getsize(prefix + ext) // 1024))


if __name__ == "__main__":
    main()
