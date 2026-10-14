import 'package:xterm/src/core/cell.dart';

class CursorStyle {
  int foreground;

  int background;

  int attrs;

  CursorStyle({this.foreground = 0, this.background = 0, this.attrs = 0});

  static final empty = CursorStyle();

  /// The bits a palette index or one RGB component may occupy.
  /// `value & ~_colorByteMask` is non-zero exactly when the value is above 255
  /// or below 0, since a negative int has all its high bits set.
  static const _colorByteMask = 0xff;

  void setBold() {
    attrs |= CellAttr.bold;
  }

  void setFaint() {
    attrs |= CellAttr.faint;
  }

  void setItalic() {
    attrs |= CellAttr.italic;
  }

  void setUnderline() {
    attrs |= CellAttr.underline;
  }

  void setBlink() {
    attrs |= CellAttr.blink;
  }

  void setInverse() {
    attrs |= CellAttr.inverse;
  }

  void setInvisible() {
    attrs |= CellAttr.invisible;
  }

  void setStrikethrough() {
    attrs |= CellAttr.strikethrough;
  }

  void unsetBold() {
    attrs &= ~CellAttr.bold;
  }

  void unsetFaint() {
    attrs &= ~CellAttr.faint;
  }

  void unsetItalic() {
    attrs &= ~CellAttr.italic;
  }

  void unsetUnderline() {
    attrs &= ~CellAttr.underline;
  }

  void unsetBlink() {
    attrs &= ~CellAttr.blink;
  }

  void unsetInverse() {
    attrs &= ~CellAttr.inverse;
  }

  void unsetInvisible() {
    attrs &= ~CellAttr.invisible;
  }

  void unsetStrikethrough() {
    attrs &= ~CellAttr.strikethrough;
  }

  bool get isBold => (attrs & CellAttr.bold) != 0;

  bool get isFaint => (attrs & CellAttr.faint) != 0;

  bool get isItalis => (attrs & CellAttr.italic) != 0;

  bool get isUnderline => (attrs & CellAttr.underline) != 0;

  bool get isBlink => (attrs & CellAttr.blink) != 0;

  bool get isInverse => (attrs & CellAttr.inverse) != 0;

  bool get isInvisible => (attrs & CellAttr.invisible) != 0;

  void setForegroundColor16(int color) {
    foreground = color | CellColor.named;
  }

  void setForegroundColor256(int color) {
    // An index outside 0..255 has no palette entry to paint, so the color
    // stays as it was.
    if ((color & ~_colorByteMask) != 0) {
      return;
    }

    foreground = color | CellColor.palette;
  }

  void setForegroundColorRgb(int r, int g, int b) {
    // A component outside 0..255 would spill into its neighbor or into the
    // color type, so the color stays as it was. A bit outside the mask in any
    // component survives the OR, so one test covers all three.
    if (((r | g | b) & ~_colorByteMask) != 0) {
      return;
    }

    foreground = (r << 16) | (g << 8) | b | CellColor.rgb;
  }

  void resetForegroundColor() {
    foreground = 0; // | CellColor.normal;
  }

  void setBackgroundColor16(int color) {
    background = color | CellColor.named;
  }

  void setBackgroundColor256(int color) {
    // An index outside 0..255 has no palette entry to paint, so the color
    // stays as it was.
    if ((color & ~_colorByteMask) != 0) {
      return;
    }

    background = color | CellColor.palette;
  }

  void setBackgroundColorRgb(int r, int g, int b) {
    // A component outside 0..255 would spill into its neighbor or into the
    // color type, so the color stays as it was. A bit outside the mask in any
    // component survives the OR, so one test covers all three.
    if (((r | g | b) & ~_colorByteMask) != 0) {
      return;
    }

    background = (r << 16) | (g << 8) | b | CellColor.rgb;
  }

  void resetBackgroundColor() {
    background = 0; // | CellColor.normal;
  }

  void reset() {
    foreground = 0;
    background = 0;
    attrs = 0;
  }
}

class CursorPosition {
  int x;

  int y;

  CursorPosition(this.x, this.y);
}
