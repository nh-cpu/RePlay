"""Build reusable atlas crops and nine-slice menu themes; keep source artwork intact."""
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parents[1] / "afterimage-2.0"
MENU = ROOT / "assets/menu"


def build():
    MENU.mkdir(exist_ok=True)
    # Half-resolution atlas keeps nine-slice corners proportional to 44–56 px controls.
    with Image.open(ROOT / "Monochrome rhythm game menu sprite atlas.png") as atlas:
        atlas.resize((atlas.width // 2, atlas.height // 2), Image.Resampling.LANCZOS).save(MENU / "menu_atlas.png")
    regions = {
        "button": (22, 105, 285, 116),
        "button_pressed": (639, 105, 289, 116),
        "button_dark": (945, 105, 289, 116),
        "panel_ivory": (22, 295, 597, 270),
        "panel": (634, 295, 600, 270),
        "song": (19, 629, 598, 173),
        "song_selected": (647, 629, 588, 173),
        "back": (39, 872, 105, 125),
        "play": (333, 872, 107, 125),
        "retry": (945, 865, 137, 140),
        "close": (1105, 873, 123, 123),
        "diamond": (630, 682, 69, 74),
    }
    for name, rect in regions.items():
        (MENU / f"{name}.tres").write_text(
            '[gd_resource type="AtlasTexture" format=3]\n\n'
            '[ext_resource type="Texture2D" path="res://assets/menu/menu_atlas.png" id="1"]\n\n'
            '[resource]\natlas = ExtResource("1")\nregion = Rect2(%s)\nfilter_clip = true\n'
            % ", ".join(str(value / 2) for value in rect), encoding="utf-8")
    for weight, value in {"regular": 400, "medium": 500, "semibold": 600, "bold": 700, "title": 700}.items():
        (ROOT / f"assets/fonts/outfit_{weight}.tres").write_text(
            '[gd_resource type="FontVariation" format=3]\n\n'
            '[ext_resource type="FontFile" path="res://assets/fonts/Outfit.ttf" id="1"]\n\n'
            + ('[resource]\nbase_font = ExtResource("1")\nvariation_opentype = {2003265652: %d.0}\n' % value)
            + ('spacing_glyph = 1\n' if weight == "title" else ''),
            encoding="utf-8")

    parts = ['[gd_resource type="Theme" format=3]\n']
    for name in regions:
        parts.append(f'[ext_resource type="Texture2D" path="res://assets/menu/{name}.tres" id="{name}"]')
    for name in ("regular", "medium", "semibold", "bold", "title"):
        parts.append(f'[ext_resource type="FontVariation" path="res://assets/fonts/outfit_{name}.tres" id="{name}"]')

    def box(name, texture, edge, margins):
        parts.append(f'\n[sub_resource type="StyleBoxTexture" id="{name}"]')
        for side, value in zip(("left", "top", "right", "bottom"), margins):
            parts.append(f'content_margin_{side} = {float(value)}')
        parts.append(f'texture = ExtResource("{texture}")')
        for side in ("left", "top", "right", "bottom"):
            inset = edge / 2
            if name in ("row", "selected") and side in ("top", "bottom"):
                inset = 14
            parts.append(f'texture_margin_{side} = {float(inset)}')

    box("button", "button", 54, (24, 12, 24, 12))
    box("pressed", "button_pressed", 54, (24, 13, 24, 11))
    box("disabled", "button_dark", 54, (24, 12, 24, 12))
    box("panel", "panel", 44, (26, 24, 26, 24))
    box("row", "song", 36, (20, 18, 20, 18))
    box("selected", "song", 36, (20, 18, 20, 18))
    parts.append('modulate_color = Color(1.2, 1.17, 1.1, 1)')
    parts.append('expand_margin_left = 10.0')
    parts += [
        '\n[sub_resource type="StyleBoxFlat" id="focus"]',
        'bg_color = Color(0, 0, 0, 0)',
        'border_width_left = 2', 'border_width_top = 2',
        'border_width_right = 2', 'border_width_bottom = 2',
        'border_color = Color(0.96, 0.93, 0.85, 0.65)',
        'corner_radius_top_left = 24', 'corner_radius_top_right = 24',
        'corner_radius_bottom_left = 24', 'corner_radius_bottom_right = 24',
        '\n[sub_resource type="StyleBoxFlat" id="input"]',
        'content_margin_left = 16.0', 'content_margin_right = 16.0',
        'content_margin_top = 10.0', 'content_margin_bottom = 10.0',
        'bg_color = Color(0.075, 0.076, 0.085, 1)',
        'border_width_bottom = 1', 'border_color = Color(0.55, 0.53, 0.48, 0.5)',
        'corner_radius_top_left = 10', 'corner_radius_top_right = 10',
        'corner_radius_bottom_left = 10', 'corner_radius_bottom_right = 10',
        '\n[sub_resource type="StyleBoxEmpty" id="empty"]',
        '\n[resource]', 'default_font = ExtResource("regular")', 'default_font_size = 18',
    ]
    ivory = 'Color(0.94, 0.92, 0.87, 1)'
    charcoal = 'Color(0.14, 0.14, 0.16, 1)'
    for kind in ("Button", "OptionButton"):
        parts += [f'{kind}/fonts/font = ExtResource("semibold")']
        for state in ("normal", "hover", "pressed", "hover_pressed", "disabled", "focus"):
            style = {"normal": "button", "hover": "button", "pressed": "pressed", "hover_pressed": "pressed", "disabled": "disabled", "focus": "focus"}[state]
            parts.append(f'{kind}/styles/{state} = SubResource("{style}")')
        for state in ("", "hover_", "pressed_", "hover_pressed_", "focus_"):
            parts.append(f'{kind}/colors/font_{state}color = {charcoal}')
            parts.append(f'{kind}/colors/icon_{state}color = {charcoal}')
        parts.append(f'{kind}/colors/font_disabled_color = Color(0.55, 0.54, 0.52, 1)')
    parts += [
        f'Label/colors/font_color = {ivory}',
        'TitleLabel/base_type = &"Label"', 'TitleLabel/fonts/font = ExtResource("title")',
        'TitleLabel/font_sizes/font_size = 44',
        'SectionLabel/base_type = &"Label"', 'SectionLabel/fonts/font = ExtResource("semibold")',
        'SectionLabel/font_sizes/font_size = 13',
        'SectionLabel/colors/font_color = Color(0.68, 0.66, 0.61, 1)',
        'ScoreLabel/base_type = &"Label"', 'ScoreLabel/fonts/font = ExtResource("bold")',
        'PanelContainer/styles/panel = SubResource("panel")',
        'ItemList/fonts/font = ExtResource("medium")',
        'ItemList/font_sizes/font_size = 22',
        f'ItemList/colors/font_color = {ivory}', f'ItemList/colors/font_selected_color = {ivory}',
        'ItemList/constants/line_separation = 12',
        'ItemList/constants/v_separation = 22',
        'ItemList/styles/panel = SubResource("panel")',
        'ItemList/styles/selected = SubResource("selected")',
        'ItemList/styles/selected_focus = SubResource("selected")',
        'ItemList/styles/cursor = SubResource("empty")',
        'ItemList/styles/cursor_unfocused = SubResource("empty")',
        'LibraryList/base_type = &"ItemList"',
        'LibraryList/styles/panel = SubResource("empty")',
        'CheckButton/styles/normal = SubResource("empty")',
        'CheckButton/styles/hover = SubResource("empty")',
        'CheckButton/styles/pressed = SubResource("empty")',
        'CheckButton/styles/focus = SubResource("focus")',
        f'CheckButton/colors/font_color = {ivory}',
        f'CheckButton/colors/font_hover_color = {ivory}',
        f'CheckButton/colors/font_pressed_color = {ivory}',
        'CheckButton/font_sizes/font_size = 16',
        'CheckButton/constants/h_separation = 12',
        'IconButton/base_type = &"Button"',
        'IconButton/styles/normal = SubResource("empty")',
        'IconButton/styles/hover = SubResource("focus")',
        'IconButton/styles/pressed = SubResource("input")',
        'IconButton/styles/disabled = SubResource("empty")',
        'IconButton/styles/focus = SubResource("focus")',
        f'IconButton/colors/icon_normal_color = {ivory}',
        f'IconButton/colors/icon_hover_color = {ivory}',
        f'IconButton/colors/icon_pressed_color = {ivory}',
    ]
    for kind in ("LineEdit", "TextEdit", "PopupMenu"):
        parts += [f'{kind}/colors/font_color = {ivory}']
        parts += [f'{kind}/styles/{s} = SubResource("input")' for s in ("normal", "read_only")]
    parts += ['PopupMenu/styles/panel = SubResource("panel")',
              'PopupMenu/styles/hover = SubResource("input")']
    # The wheel redesign uses flatter surfaces; atlas textures remain reusable accents.
    insert = parts.index('\n[resource]')
    flat = []
    for name, color, border in [
        ("flat_button", "Color(0.92, 0.90, 0.84, 1)", "Color(0.92, 0.90, 0.84, 1)"),
        ("flat_hover", "Color(1, 0.98, 0.92, 1)", "Color(1, 1, 0.95, 1)"),
        ("flat_pressed", "Color(0.72, 0.71, 0.67, 1)", "Color(0.86, 0.84, 0.78, 1)"),
        ("flat_panel", "Color(0.075, 0.075, 0.09, 0.97)", "Color(0.34, 0.33, 0.30, 1)"),
        ("card", "Color(0.13, 0.13, 0.15, 1)", "Color(0.28, 0.28, 0.29, 1)"),
    ]:
        flat += [f'\n[sub_resource type="StyleBoxFlat" id="{name}"]',
                 f'bg_color = {color}', f'border_color = {border}']
        for side in ("left", "top", "right", "bottom"):
            flat += [f'border_width_{side} = 1',
                     f'content_margin_{side} = {24.0 if name == "flat_panel" else (18.0 if side in ("left", "right") else 10.0)}']
        for corner in ("top_left", "top_right", "bottom_left", "bottom_right"):
            flat.append(f'corner_radius_{corner} = 5')
    parts[insert:insert] = flat
    for index, line in enumerate(parts):
        if line.startswith(('Button/styles/', 'OptionButton/styles/')):
            line = line.replace('SubResource("button")', 'SubResource("flat_button")')
            line = line.replace('SubResource("pressed")', 'SubResource("flat_pressed")')
            if '/styles/hover =' in line:
                line = line.replace('SubResource("flat_button")', 'SubResource("flat_hover")')
        if line.startswith(('PanelContainer/styles/', 'PopupMenu/styles/panel')):
            line = line.replace('SubResource("panel")', 'SubResource("flat_panel")')
        parts[index] = line
    parts += ['SongCard/styles/normal = SubResource("card")',
              'SongTitle/base_type = &"Label"',
              'SongTitle/fonts/font = ExtResource("semibold")',
              'SongTitle/font_sizes/font_size = 22']
    (MENU / "menu_theme.tres").write_text("\n".join(parts) + "\n", encoding="utf-8")


if __name__ == "__main__":
    build()
