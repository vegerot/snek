#!/usr/bin/env python3

import argparse
import sys

from pilmoji import Pilmoji
from pilmoji.source import MicrosoftEmojiSource, AppleEmojiSource, GoogleEmojiSource
from PIL import Image, ImageDraw, ImageFont


def create_png_from_char(char, emoji_source, font_size, output_path):
    font = ImageFont.load_default(font_size)

    # Calculate the width and height of the text to be drawn
    bbox_left, bbox_top, bbox_right, bbox_bottom  = font.getbbox(char)

    image = Image.new("RGBA", (2* bbox_right, int(bbox_bottom*1.1)), "#00000000")
    draw = Pilmoji(image, source=emoji_source)

    draw.text(
        (0, -bbox_bottom),
        char,
        fill="#00000000",
        font=font,
        embedded_color=True,
    )

    if output_path:
        image.save(output_path)
        print(f"Image saved to {output_path}")
    else:
        image.show()



def main():
    parser = argparse.ArgumentParser(
        description="Create a PNG image from a text character."
    )
    parser.add_argument(
        "input", type=str, help="The character to create a PNG from."
    )
    # pick flavor based on OS
    default_flavor = AppleEmojiSource if "darwin" in sys.platform else (
        MicrosoftEmojiSource if ("win32" in sys.platform and False) # FIXME: https://github.com/jay3332/pilmoji/issues/38#issuecomment-2692015761
        else GoogleEmojiSource
    )
    parser.add_argument("--flavor", type=str, default=default_flavor, help="Emoji flavor.")
    parser.add_argument("--fontsize", type=int, default=96, help="Font size.")
    parser.add_argument("--output", type=str, help="Output file path.")

    args = parser.parse_args()

    create_png_from_char(
        args.input,
        emoji_source=args.flavor,
        font_size=args.fontsize,
        output_path=args.output,
    )


"""
I created the textures in this game with
    ./text-to-png \
          '🍏🍎🍐🍊🍋🍌🍉🍇🍓🍈🍒🍑🍍🥭🥥🥝🍅🍆🌽🥕🥔🥬🥒🥦🍞🥖🥯🥨🥞🧇🍳🍔🍟🍕🌭🥗🍝🍜🍲🍣🍱🍤🍙🍚🍛🍥🍦🍧🍨🍩🍪🎂🍰🧁🍫🍬🍭🍮🍯🥛☕🍵🍺🍻🥂🍷🥃' \
            --output=emoji.png
"""
if __name__ == "__main__":
    main()
