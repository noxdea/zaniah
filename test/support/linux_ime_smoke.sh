#!/bin/sh
set -eu

export DISPLAY=:99
export LANG=C.UTF-8
export LC_ALL=C.UTF-8
export XMODIFIERS=@im=ibus
export GTK_IM_MODULE=ibus
export QT_IM_MODULE=ibus

Xvfb "$DISPLAY" -screen 0 800x600x24 +extension GLX >/tmp/zaniah-xvfb.log 2>&1 &
xvfb_pid=$!
trap 'kill "$xvfb_pid" 2>/dev/null || true' EXIT
sleep 2

gsettings set org.freedesktop.ibus.general preload-engines "['kkc']"
gsettings set org.freedesktop.ibus.general engines-order "['kkc']"
gsettings set org.freedesktop.ibus.general enable-by-default true
ibus-daemon --daemonize --xim --desktop=none --panel=disable --emoji-extension=disable
sleep 3

ruby examples/native_ime.rb
ruby examples/gallery.rb --backend=native --check
