# /// script
# requires-python = ">=3.11"
# dependencies = ["fonttools==4.63.0"]
# ///
"""Bake the bundled Flutter variable fonts for GPUI's face-based selector."""

from pathlib import Path

from fontTools.ttLib import TTFont
from fontTools.varLib.instancer import instantiateVariableFont


def main() -> None:
    crate = Path(__file__).resolve().parents[1]
    source_dir = crate.parents[1] / "assets" / "fonts"
    output_dir = crate / "assets" / "fonts" / "static"
    output_dir.mkdir(parents=True, exist_ok=True)

    for stem in ("Inter", "JetBrainsMono"):
        source = TTFont(source_dir / f"{stem}-Variable.ttf", recalcTimestamp=False)
        axes = {axis.axisTag: axis.defaultValue for axis in source["fvar"].axes}
        weight_axis = next(axis for axis in source["fvar"].axes if axis.axisTag == "wght")
        for weight in range(int(weight_axis.minValue), int(weight_axis.maxValue) + 1, 100):
            instance = instantiateVariableFont(
                source,
                {**axes, "wght": weight},
                updateFontNames=True,
                static=True,
            )
            instance.recalcTimestamp = False
            assert "fvar" not in instance
            assert instance["OS/2"].usWeightClass == weight
            assert instance["name"].getDebugName(13) == source["name"].getDebugName(13)
            output = output_dir / f"{stem}-{weight}.ttf"
            instance.save(output)
            print(f"{output.name}: {instance['name'].getDebugName(1)} / "
                  f"{instance['name'].getDebugName(16)} / {instance['name'].getDebugName(2)}")


if __name__ == "__main__":
    main()
