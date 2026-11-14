"""Draw the addon's small custom icons as WoW-compatible TGA files
(32-bit, uncompressed, power-of-two size).

Usage: python -I tools/make_icons.py <pillow-lib-dir> <out-dir>
"""
import sys

sys.path.insert(0, sys.argv[1])
from PIL import Image, ImageDraw  # noqa: E402

OUT = sys.argv[2]
S = 4  # supersampling factor
GOLD, DARK, RIM = (255, 209, 0, 255), (40, 28, 10, 255), (200, 162, 74, 255)


def finish(img, name, size):
    img.resize((size, size), Image.LANCZOS).save(f"{OUT}/{name}.tga")


def chain():
    """Quest chain: gold circle with two linked rings."""
    n = 32 * S
    img = Image.new("RGBA", (n, n), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.ellipse((1 * S, 1 * S, 31 * S, 31 * S), fill=DARK, outline=RIM, width=2 * S)
    w = 3 * S
    d.rounded_rectangle((6 * S, 11 * S, 19 * S, 21 * S), radius=5 * S, outline=GOLD, width=w)
    d.rounded_rectangle((13 * S, 11 * S, 26 * S, 21 * S), radius=5 * S, outline=GOLD, width=w)
    finish(img, "Chain", 32)


def ring():
    """Gold ring drawn around round boss portraits."""
    n = 64 * S
    img = Image.new("RGBA", (n, n), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.ellipse((1 * S, 1 * S, 63 * S, 63 * S), outline=(0, 0, 0, 255), width=2 * S)
    d.ellipse((2 * S, 2 * S, 62 * S, 62 * S), outline=(217, 178, 90, 255), width=4 * S)
    d.ellipse((5 * S, 5 * S, 59 * S, 59 * S), outline=(90, 66, 24, 255), width=1 * S)
    finish(img, "Ring", 64)


def circle_mask():
    """White disc used as a mask to make portraits round."""
    n = 64 * S
    img = Image.new("RGBA", (n, n), (0, 0, 0, 0))
    ImageDraw.Draw(img).ellipse((3 * S, 3 * S, 61 * S, 61 * S), fill=(255, 255, 255, 255))
    finish(img, "CircleMask", 64)


chain()
ring()
circle_mask()
print("icons written to", OUT)
