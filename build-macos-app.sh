#!/bin/bash

BREW_PREFIX=$(brew --prefix)

meson compile -C builddir

rm -rf Amberol.app
mkdir -p Amberol.app/Contents/{MacOS,Resources,lib/gstreamer-1.0,lib/gdk-pixbuf-2.0/2.10.0/loaders,share/amberol,share/glib-2.0/schemas,share/icons/hicolor/scalable/apps,share/icons/hicolor/symbolic/apps}

cp builddir/src/amberol Amberol.app/Contents/MacOS/
cp builddir/src/amberol.gresource Amberol.app/Contents/share/amberol/
cp data/io.bassi.Amberol.gschema.xml Amberol.app/Contents/share/glib-2.0/schemas/
glib-compile-schemas Amberol.app/Contents/share/glib-2.0/schemas/
cp data/icons/hicolor/scalable/apps/*.svg Amberol.app/Contents/share/icons/hicolor/scalable/apps/
cp data/icons/hicolor/symbolic/apps/*.svg Amberol.app/Contents/share/icons/hicolor/symbolic/apps/

mkdir -p Amberol.iconset
rsvg-convert -w 16 -h 16 data/icons/hicolor/scalable/apps/io.bassi.Amberol.svg -o Amberol.iconset/icon_16x16.png
rsvg-convert -w 32 -h 32 data/icons/hicolor/scalable/apps/io.bassi.Amberol.svg -o Amberol.iconset/icon_32x32.png
rsvg-convert -w 128 -h 128 data/icons/hicolor/scalable/apps/io.bassi.Amberol.svg -o Amberol.iconset/icon_128x128.png
rsvg-convert -w 256 -h 256 data/icons/hicolor/scalable/apps/io.bassi.Amberol.svg -o Amberol.iconset/icon_256x256.png
rsvg-convert -w 512 -h 512 data/icons/hicolor/scalable/apps/io.bassi.Amberol.svg -o Amberol.iconset/icon_512x512.png
iconutil -c icns Amberol.iconset -o Amberol.app/Contents/Resources/Amberol.icns
rm -rf Amberol.iconset

cat > Amberol.app/Contents/Info.plist << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>amberol-launcher</string>
    <key>CFBundleIconFile</key><string>Amberol.icns</string>
    <key>CFBundleIdentifier</key><string>io.bassi.Amberol</string>
    <key>CFBundleName</key><string>Amberol</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleVersion</key><string>1.0</string>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

cat > Amberol.app/Contents/MacOS/amberol-launcher << 'LAUNCHER'
#!/bin/bash
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
CONTENTS="$DIR/.."
export DYLD_LIBRARY_PATH="$CONTENTS/lib:$DYLD_LIBRARY_PATH"
export GST_PLUGIN_PATH="$CONTENTS/lib/gstreamer-1.0"
export GSETTINGS_SCHEMA_DIR="$CONTENTS/share/glib-2.0/schemas"
export AMBEROL_PKGDATADIR="$CONTENTS/share/amberol"
export GTK_PATH="$CONTENTS/lib/gtk-4.0"
export GDK_PIXBUF_MODULE_FILE="$CONTENTS/lib/gdk-pixbuf-2.0/2.10.0/loaders.cache"
export XDG_DATA_DIRS="$CONTENTS/share:${XDG_DATA_DIRS:-/usr/local/share:/usr/share}"
exec "$DIR/amberol" "$@"
LAUNCHER
chmod +x Amberol.app/Contents/MacOS/amberol-launcher

otool -L Amberol.app/Contents/MacOS/amberol | grep "$BREW_PREFIX" | awk '{print $1}' | xargs -I{} cp -L {} Amberol.app/Contents/lib/
for i in {1..5}; do
  for lib in Amberol.app/Contents/lib/*.dylib; do
    [ -f "$lib" ] && otool -L "$lib" 2>/dev/null | grep "$BREW_PREFIX" | awk '{print $1}' | while read dep; do
      [ -f "$dep" ] && [ ! -f "Amberol.app/Contents/lib/$(basename $dep)" ] && cp -L "$dep" Amberol.app/Contents/lib/
    done
  done
done

cp -L "$BREW_PREFIX"/lib/gstreamer-1.0/*.dylib Amberol.app/Contents/lib/gstreamer-1.0/
cp -L "$BREW_PREFIX"/lib/gdk-pixbuf-2.0/2.10.0/loaders/*.so Amberol.app/Contents/lib/gdk-pixbuf-2.0/2.10.0/loaders/

for lib in Amberol.app/Contents/lib/*.dylib; do
  LIBNAME=$(basename "$lib")
  install_name_tool -change "$BREW_PREFIX/lib/$LIBNAME" "@executable_path/../lib/$LIBNAME" Amberol.app/Contents/MacOS/amberol 2>/dev/null || true
  install_name_tool -id "@executable_path/../lib/$LIBNAME" "$lib" 2>/dev/null || true
  for dep in Amberol.app/Contents/lib/*.dylib; do
    DEPNAME=$(basename "$dep")
    install_name_tool -change "$BREW_PREFIX/lib/$DEPNAME" "@executable_path/../lib/$DEPNAME" "$lib" 2>/dev/null || true
  done
done

for plugin in Amberol.app/Contents/lib/gstreamer-1.0/*.dylib; do
  for dep in Amberol.app/Contents/lib/*.dylib; do
    DEPNAME=$(basename "$dep")
    install_name_tool -change "$BREW_PREFIX/lib/$DEPNAME" "@executable_path/../lib/$DEPNAME" "$plugin" 2>/dev/null || true
  done
done

GDK_PIXBUF_MODULEDIR=Amberol.app/Contents/lib/gdk-pixbuf-2.0/2.10.0/loaders \
  "$BREW_PREFIX/bin/gdk-pixbuf-query-loaders" \
  Amberol.app/Contents/lib/gdk-pixbuf-2.0/2.10.0/loaders/*.so \
  > Amberol.app/Contents/lib/gdk-pixbuf-2.0/2.10.0/loaders.cache

find Amberol.app/Contents/lib -name "*.dylib" -o -name "*.so" | xargs -I{} codesign --force --sign - {}
codesign --force --sign - Amberol.app/Contents/MacOS/amberol

echo "Done! Drag Amberol.app to /Applications"
