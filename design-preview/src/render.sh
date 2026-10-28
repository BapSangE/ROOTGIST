#!/bin/zsh
# 사용: render.sh <html 이름(확장자 없이)> [출력 이름] [#y=스크롤]
# 402×874pt 화면을 3배(1206×2622px)로 찍는다.
cd "$(dirname "$0")"
in=$1; out=${2:-$1}; hash=${3:-}
"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" --headless=new --disable-gpu --hide-scrollbars \
  --allow-file-access-from-files --force-device-scale-factor=3 --window-size=402,874 --virtual-time-budget=1500 \
  --screenshot="$PWD/../screens/$out.png" "file://$PWD/$in.html$hash" >/dev/null 2>&1
echo "$out.png $(sips -g pixelWidth -g pixelHeight ../screens/$out.png | tail -2 | awk '{print $2}' | tr '\n' 'x')"
